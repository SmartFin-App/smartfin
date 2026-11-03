package routes

import (
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
)

func TestAdminGuard(t *testing.T) {
	cases := []struct {
		name      string
		configKey string
		sentKey   string
		want      int
	}{
		{"no key configured disables the routes", "", "anything", fiber.StatusNotFound},
		{"missing header is refused", "s3cret", "", fiber.StatusUnauthorized},
		{"wrong key is refused", "s3cret", "guess", fiber.StatusUnauthorized},
		{"matching key passes", "s3cret", "s3cret", fiber.StatusOK},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			app := fiber.New()
			admin := app.Group("/admin", adminGuard(tc.configKey))
			admin.Delete("/reset-transactions", func(c *fiber.Ctx) error { return c.SendStatus(fiber.StatusOK) })

			req := httptest.NewRequest("DELETE", "/admin/reset-transactions", nil)
			if tc.sentKey != "" {
				req.Header.Set(AdminKeyHeader, tc.sentKey)
			}
			resp, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			if resp.StatusCode != tc.want {
				t.Fatalf("status = %d, want %d", resp.StatusCode, tc.want)
			}
		})
	}
}
