// Package auth verifies the Firebase ID token on every /api request and makes
// sure a request only ever names the signed-in user.
//
// Before this package the API trusted whatever UID it was sent, so anyone who
// knew a UID could read or wipe that user's data (defect D-02 / NFR-04).
package auth

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	fbauth "firebase.google.com/go/v4/auth"
	"github.com/gofiber/fiber/v2"
	"google.golang.org/api/option"
)

// DefaultProjectID is the Firebase project the app signs users in to. Tokens
// issued for any other project are refused. FIREBASE_PROJECT_ID overrides it.
const DefaultProjectID = "fir-auth-login-udacity"

// AdminKeyHeader is the header the /admin routes and the evaluation harnesses
// send. It matches routes.AdminKeyHeader.
const AdminKeyHeader = "X-Admin-Key"

// localsUID and localsHarness are the c.Locals keys this package sets.
const (
	localsUID     = "auth_uid"
	localsHarness = "auth_harness"
)

// testUIDPrefixes are the made-up users the evaluation harnesses (cmd/eval,
// cmd/slipeval) and the test-design API driver create. A request carrying the
// admin key may act as one of these, never as a real user: Firebase UIDs are
// 28 alphanumeric characters and never contain a hyphen.
var testUIDPrefixes = []string{"eval-", "tds-"}

// Verifier checks a Firebase ID token and returns the UID it was issued to.
type Verifier interface {
	VerifyIDToken(ctx context.Context, idToken string) (string, error)
}

type firebaseVerifier struct{ client *fbauth.Client }

func (v firebaseVerifier) VerifyIDToken(ctx context.Context, idToken string) (string, error) {
	tok, err := v.client.VerifyIDToken(ctx, idToken)
	if err != nil {
		return "", err
	}
	return tok.UID, nil
}

// NewFirebaseVerifier builds a verifier for the project in FIREBASE_PROJECT_ID
// (default DefaultProjectID). Verifying a token needs only the project ID and
// Google's public signing keys, so no service-account credentials are used,
// locally or on Cloud Run.
func NewFirebaseVerifier(ctx context.Context) (Verifier, error) {
	projectID := strings.TrimSpace(os.Getenv("FIREBASE_PROJECT_ID"))
	if projectID == "" {
		projectID = DefaultProjectID
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID}, option.WithoutAuthentication())
	if err != nil {
		return nil, fmt.Errorf("firebase app: %w", err)
	}
	client, err := app.Auth(ctx)
	if err != nil {
		return nil, fmt.Errorf("firebase auth client: %w", err)
	}
	return firebaseVerifier{client: client}, nil
}

// Middleware authenticates a request and checks every user ID it carries.
//
// A request is let through when it has either
//   - "Authorization: Bearer <Firebase ID token>" that verifies, or
//   - the admin key (adminKey, from ADMIN_API_KEY), in which case it may only
//     name test users (see testUIDPrefixes).
//
// It answers 401 when neither is present or the token is invalid, and 403 when
// a user_id or firebase_uid in the query string, JSON body or form names
// anyone else. Path parameters are checked per route by OwnParam, because a
// group middleware runs before the route's parameters are known.
func Middleware(v Verifier, adminKey string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		harness := adminKey != "" && c.Get(AdminKeyHeader) != "" &&
			subtle.ConstantTimeCompare([]byte(c.Get(AdminKeyHeader)), []byte(adminKey)) == 1

		var uid string
		if !harness {
			token, ok := bearerToken(c.Get(fiber.HeaderAuthorization))
			if !ok {
				return unauthorized(c, "missing Firebase ID token")
			}
			var err error
			uid, err = v.VerifyIDToken(c.UserContext(), token)
			if err != nil || uid == "" {
				return unauthorized(c, "invalid or expired Firebase ID token")
			}
		}
		c.Locals(localsUID, uid)
		c.Locals(localsHarness, harness)

		for _, claimed := range claimedUIDs(c) {
			if !allowed(c, claimed) {
				return forbidden(c)
			}
		}
		return c.Next()
	}
}

// OwnParam refuses the request unless the named path parameter is the
// authenticated user (or, for a harness request, a test user).
func OwnParam(name string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if !allowed(c, strings.TrimSpace(c.Params(name))) {
			return forbidden(c)
		}
		return c.Next()
	}
}

// UID returns the verified UID of the request, or "" for a harness request.
func UID(c *fiber.Ctx) string {
	uid, _ := c.Locals(localsUID).(string)
	return uid
}

func allowed(c *fiber.Ctx, claimed string) bool {
	if claimed == "" {
		return true // the handler reports a missing ID as 400
	}
	if harness, _ := c.Locals(localsHarness).(bool); harness {
		return isTestUID(claimed)
	}
	uid := UID(c)
	return uid != "" && claimed == uid
}

func isTestUID(uid string) bool {
	for _, p := range testUIDPrefixes {
		if strings.HasPrefix(uid, p) && len(uid) > len(p) {
			return true
		}
	}
	return false
}

func bearerToken(header string) (string, bool) {
	const prefix = "Bearer "
	if len(header) <= len(prefix) || !strings.EqualFold(header[:len(prefix)], prefix) {
		return "", false
	}
	token := strings.TrimSpace(header[len(prefix):])
	return token, token != ""
}

// claimedUIDs collects every user ID the request names outside its path: the
// user_id / firebase_uid query parameters, the same fields of a JSON body, and
// the user_id field of a form (the scanner's multipart upload).
func claimedUIDs(c *fiber.Ctx) []string {
	var ids []string
	add := func(s string) {
		if s = strings.TrimSpace(s); s != "" {
			ids = append(ids, s)
		}
	}
	add(c.Query("user_id"))
	add(c.Query("firebase_uid"))

	ctype := strings.ToLower(c.Get(fiber.HeaderContentType))
	switch {
	case strings.HasPrefix(ctype, fiber.MIMEApplicationJSON):
		var body struct {
			UserID      any `json:"user_id"`
			FirebaseUID any `json:"firebase_uid"`
		}
		// A malformed body is the handler's to reject with 400.
		if err := json.Unmarshal(c.Body(), &body); err == nil {
			for _, v := range []any{body.UserID, body.FirebaseUID} {
				switch s := v.(type) {
				case nil:
				case string:
					add(s)
				default:
					// A non-string ID can only be an attempt to slip past the
					// check; name it so it is compared and refused.
					ids = append(ids, fmt.Sprint(s))
				}
			}
		}
	case strings.HasPrefix(ctype, fiber.MIMEMultipartForm):
		if form, err := c.MultipartForm(); err == nil {
			for _, v := range form.Value["user_id"] {
				add(v)
			}
		}
	case strings.HasPrefix(ctype, fiber.MIMEApplicationForm):
		add(c.FormValue("user_id"))
	}
	return ids
}

var errForbidden = errors.New("this request names a different user than the one signed in")

func unauthorized(c *fiber.Ctx, msg string) error {
	return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": msg})
}

func forbidden(c *fiber.Ctx) error {
	return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": errForbidden.Error()})
}
