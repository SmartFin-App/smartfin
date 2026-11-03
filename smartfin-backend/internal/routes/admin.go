package routes

import (
	"crypto/subtle"

	"github.com/gofiber/fiber/v2"
)

// AdminKeyHeader carries the shared secret that unlocks the /admin routes.
const AdminKeyHeader = "X-Admin-Key"

// adminGuard lets a request through only when its X-Admin-Key header matches
// key (ADMIN_API_KEY). With no key configured the admin routes are switched
// off entirely, so a deployment that forgets the variable fails closed rather
// than leaving the seed and wipe routes open to anyone who finds the URL.
func adminGuard(key string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if key == "" {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "admin routes are disabled: ADMIN_API_KEY is not set"})
		}
		if subtle.ConstantTimeCompare([]byte(c.Get(AdminKeyHeader)), []byte(key)) != 1 {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "missing or invalid " + AdminKeyHeader})
		}
		return c.Next()
	}
}
