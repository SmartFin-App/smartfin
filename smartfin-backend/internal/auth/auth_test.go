package auth

import (
	"bytes"
	"context"
	"errors"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
)

// fakeVerifier accepts "tok-<uid>" and nothing else.
type fakeVerifier struct{}

func (fakeVerifier) VerifyIDToken(_ context.Context, token string) (string, error) {
	if uid, ok := strings.CutPrefix(token, "tok-"); ok && uid != "" {
		return uid, nil
	}
	return "", errors.New("invalid token")
}

const (
	alice    = "AliceUID0000000000000000001"
	bob      = "BobUID000000000000000000002"
	adminKey = "s3cret"
)

// newApp mirrors routes.go: the middleware on /api, OwnParam on a path UID.
// The handlers echo what they received, to show the request reached them
// intact (in particular a multipart form already parsed by the middleware).
func newApp() *fiber.App {
	app := fiber.New()
	api := app.Group("/api", Middleware(fakeVerifier{}, adminKey))
	api.Get("/transactions/:user_id", OwnParam("user_id"), func(c *fiber.Ctx) error {
		return c.SendString(c.Params("user_id"))
	})
	api.Post("/transactions", func(c *fiber.Ctx) error { return c.SendString("created") })
	api.Get("/transactions/detail/:id", func(c *fiber.Ctx) error { return c.SendString(c.Query("user_id")) })
	api.Post("/scanner/process", func(c *fiber.Ctx) error {
		form, err := c.MultipartForm()
		if err != nil {
			return err
		}
		return c.SendString(form.Value["user_id"][0] + "|" + form.File["image"][0].Filename)
	})
	return app
}

type req struct {
	method, path, auth, admin, ctype string
	body                             io.Reader
}

func do(t *testing.T, r req) (int, string) {
	t.Helper()
	hr := httptest.NewRequest(r.method, r.path, r.body)
	if r.auth != "" {
		hr.Header.Set("Authorization", r.auth)
	}
	if r.admin != "" {
		hr.Header.Set(AdminKeyHeader, r.admin)
	}
	if r.ctype != "" {
		hr.Header.Set("Content-Type", r.ctype)
	}
	resp, err := newApp().Test(hr)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

func jsonBody(s string) io.Reader { return strings.NewReader(s) }

func scanForm(t *testing.T, uid string) (io.Reader, string) {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	_ = w.WriteField("user_id", uid)
	part, _ := w.CreateFormFile("image", "slip.png")
	_, _ = part.Write([]byte("png"))
	_ = w.Close()
	return &buf, w.FormDataContentType()
}

func TestMiddleware(t *testing.T) {
	bearer := "Bearer tok-" + alice
	cases := []struct {
		name string
		r    req
		want int
	}{
		// NFR-04: no verified identity → 401.
		{"no token", req{method: "GET", path: "/api/transactions/" + alice}, http.StatusUnauthorized},
		{"invalid token", req{method: "GET", path: "/api/transactions/" + alice, auth: "Bearer forged"}, http.StatusUnauthorized},
		{"not a bearer token", req{method: "GET", path: "/api/transactions/" + alice, auth: "tok-" + alice}, http.StatusUnauthorized},
		{"empty bearer", req{method: "GET", path: "/api/transactions/" + alice, auth: "Bearer "}, http.StatusUnauthorized},
		{"lower-case scheme", req{method: "GET", path: "/api/transactions/" + alice, auth: "bearer tok-" + alice}, http.StatusOK},

		// Path parameter.
		{"own path uid", req{method: "GET", path: "/api/transactions/" + alice, auth: bearer}, http.StatusOK},
		{"other user's path uid", req{method: "GET", path: "/api/transactions/" + bob, auth: bearer}, http.StatusForbidden},

		// Query string.
		{"own query uid", req{method: "GET", path: "/api/transactions/detail/x?user_id=" + alice, auth: bearer}, http.StatusOK},
		{"other user's query uid", req{method: "GET", path: "/api/transactions/detail/x?user_id=" + bob, auth: bearer}, http.StatusForbidden},
		{"no uid at all is the handler's to reject", req{method: "GET", path: "/api/transactions/detail/x", auth: bearer}, http.StatusOK},

		// JSON body.
		{"own body uid", req{method: "POST", path: "/api/transactions", auth: bearer, ctype: "application/json", body: jsonBody(`{"user_id":"` + alice + `"}`)}, http.StatusOK},
		{"other user's body uid", req{method: "POST", path: "/api/transactions", auth: bearer, ctype: "application/json", body: jsonBody(`{"user_id":"` + bob + `"}`)}, http.StatusForbidden},
		{"other user's firebase_uid", req{method: "POST", path: "/api/transactions", auth: bearer, ctype: "application/json; charset=utf-8", body: jsonBody(`{"firebase_uid":"` + bob + `"}`)}, http.StatusForbidden},
		{"non-string uid", req{method: "POST", path: "/api/transactions", auth: bearer, ctype: "application/json", body: jsonBody(`{"user_id":["` + alice + `"]}`)}, http.StatusForbidden},
		{"query and body disagree", req{method: "POST", path: "/api/transactions?user_id=" + alice, auth: bearer, ctype: "application/json", body: jsonBody(`{"user_id":"` + bob + `"}`)}, http.StatusForbidden},

		// Admin key: test users only.
		{"admin key as eval user", req{method: "GET", path: "/api/transactions/eval-run1-a", admin: adminKey}, http.StatusOK},
		{"admin key as tds user in body", req{method: "POST", path: "/api/transactions", admin: adminKey, ctype: "application/json", body: jsonBody(`{"user_id":"tds-20261013-x"}`)}, http.StatusOK},
		{"admin key as a real user", req{method: "GET", path: "/api/transactions/" + alice, admin: adminKey}, http.StatusForbidden},
		{"admin key with a bare prefix", req{method: "GET", path: "/api/transactions/eval-", admin: adminKey}, http.StatusForbidden},
		{"wrong admin key", req{method: "GET", path: "/api/transactions/eval-run1-a", admin: "guess"}, http.StatusUnauthorized},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got, body := do(t, tc.r); got != tc.want {
				t.Fatalf("status = %d, want %d (%s)", got, tc.want, body)
			}
		})
	}
}

// The scanner's multipart upload: the user_id field is checked, and the handler
// still receives the whole form after the middleware has parsed it.
func TestMiddlewareMultipart(t *testing.T) {
	body, ctype := scanForm(t, alice)
	code, got := do(t, req{method: "POST", path: "/api/scanner/process", auth: "Bearer tok-" + alice, ctype: ctype, body: body})
	if code != http.StatusOK || got != alice+"|slip.png" {
		t.Fatalf("own upload: status %d, body %q", code, got)
	}

	body, ctype = scanForm(t, bob)
	if code, got := do(t, req{method: "POST", path: "/api/scanner/process", auth: "Bearer tok-" + alice, ctype: ctype, body: body}); code != http.StatusForbidden {
		t.Fatalf("upload for another user: status %d, body %q", code, got)
	}
}

// Every body format a handler can parse must be checked, not only the ones the
// app sends. Fiber's BodyParser also reads vendor and text JSON types, XML,
// and form keys that match a field name in any case, and each of these once
// let a signed-in user act as someone else. The handler here parses the body
// the way the real handlers do and echoes the UID it would act on.
func TestMiddlewareEveryBodyFormat(t *testing.T) {
	app := fiber.New()
	app.Group("/api", Middleware(fakeVerifier{}, adminKey)).Post("/coach/ask", func(c *fiber.Ctx) error {
		var body struct {
			UserID string `json:"user_id"`
		}
		_ = c.BodyParser(&body)
		return c.SendString(body.UserID)
	})
	formField := func(key, uid string) (string, string) {
		var buf bytes.Buffer
		w := multipart.NewWriter(&buf)
		_ = w.WriteField(key, uid)
		_ = w.Close()
		return buf.String(), w.FormDataContentType()
	}
	formats := []struct {
		name  string
		build func(uid string) (body, ctype string)
	}{
		{"json with charset", func(u string) (string, string) { return `{"user_id":"` + u + `"}`, "application/json; charset=utf-8" }},
		{"vendor json", func(u string) (string, string) { return `{"user_id":"` + u + `"}`, "application/vnd.api+json" }},
		{"text json", func(u string) (string, string) { return `{"user_id":"` + u + `"}`, "text/json" }},
		{"upper-case json key", func(u string) (string, string) { return `{"USER_ID":"` + u + `"}`, "APPLICATION/JSON" }},
		{"xml", func(u string) (string, string) { return `<r><UserID>` + u + `</UserID></r>`, "application/xml" }},
		{"text xml", func(u string) (string, string) { return `<r><UserID>` + u + `</UserID></r>`, "text/xml" }},
		{"form user_id", func(u string) (string, string) { return "user_id=" + u, "application/x-www-form-urlencoded" }},
		{"form field name", func(u string) (string, string) { return "UserID=" + u, "application/x-www-form-urlencoded" }},
		{"form lower-case field name", func(u string) (string, string) {
			return "userid=" + u, "application/x-www-form-urlencoded; charset=utf-8"
		}},
		{"multipart field name", func(u string) (string, string) { return formField("UserID", u) }},
		{"multipart user_id", func(u string) (string, string) { return formField("user_id", u) }},
	}
	send := func(t *testing.T, body, ctype string) (int, string) {
		t.Helper()
		hr := httptest.NewRequest("POST", "/api/coach/ask", strings.NewReader(body))
		hr.Header.Set("Authorization", "Bearer tok-"+alice)
		hr.Header.Set("Content-Type", ctype)
		resp, err := app.Test(hr)
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, string(b)
	}
	for _, f := range formats {
		t.Run(f.name, func(t *testing.T) {
			body, ctype := f.build(bob)
			if code, got := send(t, body, ctype); code != http.StatusForbidden {
				t.Fatalf("naming another user: status %d, handler acted as %q", code, got)
			}
			body, ctype = f.build(alice)
			if code, got := send(t, body, ctype); code != http.StatusOK || (got != alice && got != "") {
				t.Fatalf("naming yourself: status %d, handler acted as %q", code, got)
			}
		})
	}
}

func TestIsUIDKey(t *testing.T) {
	for key, want := range map[string]bool{
		"user_id": true, "UserID": true, "userid": true, "USER-ID": true, "firebase_uid": true, "FirebaseUID": true,
		"uid": false, "user": false, "message": false, "user_id_2": false,
	} {
		if got := isUIDKey(key); got != want {
			t.Errorf("isUIDKey(%q) = %v, want %v", key, got, want)
		}
	}
}

// With ADMIN_API_KEY unset, sending an empty admin key must not count as a
// match and open the harness path.
func TestMiddlewareNoAdminKeyConfigured(t *testing.T) {
	app := fiber.New()
	app.Group("/api", Middleware(fakeVerifier{}, "")).Get("/x/:user_id", OwnParam("user_id"), func(c *fiber.Ctx) error { return c.SendStatus(200) })
	hr := httptest.NewRequest("GET", "/api/x/eval-a", nil)
	hr.Header.Set(AdminKeyHeader, "anything")
	resp, err := app.Test(hr)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", resp.StatusCode)
	}
}
