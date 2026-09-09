package handlers

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// maxAvatarBytes caps an upload. Avatars are display-sized, and the client already
// downscales before sending; this is the backstop.
const maxAvatarBytes = 5 << 20 // 5 MiB

// PhotoHandler serves profile pictures out of a GridFS bucket.
//
// The stored photo_url is a RELATIVE path ("/api/users/<uid>/photo") rather than an
// absolute URL. The API's host changes between the Android emulator, a physical
// device on the LAN and anything deployed, so an absolute URL baked in at upload
// time would rot the moment the host did.
type PhotoHandler struct {
	users  *mongo.Collection
	bucket *mongo.GridFSBucket
}

// NewPhotoHandler creates a new PhotoHandler
func NewPhotoHandler() *PhotoHandler {
	return &PhotoHandler{
		users:  config.GetCollection("users"),
		bucket: config.DB.GridFSBucket(options.GridFSBucket().SetName("avatars")),
	}
}

// PhotoPath is the relative path stored on the user document.
func PhotoPath(firebaseUID string) string {
	return fmt.Sprintf("/api/users/%s/photo", firebaseUID)
}

// contentTypeFor maps an upload's declared type to one we are willing to serve.
func contentTypeFor(declared, filename string) (string, bool) {
	switch strings.ToLower(declared) {
	case "image/jpeg", "image/jpg":
		return "image/jpeg", true
	case "image/png":
		return "image/png", true
	case "image/webp":
		return "image/webp", true
	}
	// Some clients send application/octet-stream; fall back to the extension.
	switch {
	case strings.HasSuffix(strings.ToLower(filename), ".png"):
		return "image/png", true
	case strings.HasSuffix(strings.ToLower(filename), ".jpg"),
		strings.HasSuffix(strings.ToLower(filename), ".jpeg"):
		return "image/jpeg", true
	case strings.HasSuffix(strings.ToLower(filename), ".webp"):
		return "image/webp", true
	}
	return "", false
}

// deleteExisting removes any avatar already stored for this user, so re-uploading
// replaces rather than accumulating revisions.
func (h *PhotoHandler) deleteExisting(ctx context.Context, firebaseUID string) {
	cursor, err := h.bucket.Find(ctx, bson.M{"filename": firebaseUID})
	if err != nil {
		log.Printf("PhotoHandler: could not list existing avatars for %s: %v", firebaseUID, err)
		return
	}
	defer cursor.Close(ctx)

	var files []struct {
		ID bson.ObjectID `bson:"_id"`
	}
	if err := cursor.All(ctx, &files); err != nil {
		log.Printf("PhotoHandler: could not decode existing avatars for %s: %v", firebaseUID, err)
		return
	}
	for _, f := range files {
		if err := h.bucket.Delete(ctx, f.ID); err != nil {
			log.Printf("PhotoHandler: could not delete old avatar %s: %v", f.ID.Hex(), err)
		}
	}
}

// UploadPhoto handles POST /api/users/:firebase_uid/photo
func (h *PhotoHandler) UploadPhoto(c *fiber.Ctx) error {
	firebaseUID := c.Params("firebase_uid")
	if firebaseUID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid is required"})
	}

	fileHeader, err := c.FormFile("image")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "No image file provided"})
	}
	if fileHeader.Size > maxAvatarBytes {
		return c.Status(fiber.StatusRequestEntityTooLarge).JSON(fiber.Map{
			"error": "Image is too large (max 5MB)",
		})
	}

	contentType, ok := contentTypeFor(fileHeader.Header.Get("Content-Type"), fileHeader.Filename)
	if !ok {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Unsupported image type, use JPEG, PNG or WebP",
		})
	}

	file, err := fileHeader.Open()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to read image"})
	}
	defer file.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	h.deleteExisting(ctx, firebaseUID)

	// Stored under the UID as filename so a download-by-name resolves without a
	// second lookup.
	uploadOpts := options.GridFSUpload().SetMetadata(bson.M{
		"user_id":      firebaseUID,
		"content_type": contentType,
		"uploaded_at":  time.Now(),
	})
	if _, err := h.bucket.UploadFromStream(ctx, firebaseUID, io.LimitReader(file, maxAvatarBytes), uploadOpts); err != nil {
		log.Printf("PhotoHandler: upload failed for %s: %v", firebaseUID, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to store image"})
	}

	path := PhotoPath(firebaseUID)
	res, err := h.users.UpdateOne(ctx,
		bson.M{"firebase_uid": firebaseUID},
		bson.M{"$set": bson.M{"photo_url": path, "updated_at": time.Now()}},
	)
	if err != nil {
		log.Printf("PhotoHandler: stored image but could not update photo_url for %s: %v", firebaseUID, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to update profile"})
	}
	if res.MatchedCount == 0 {
		// No profile to point at the image, so don't leave the file orphaned in the
		// bucket with nothing referencing it.
		h.deleteExisting(ctx, firebaseUID)
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "User not found"})
	}

	log.Printf("PhotoHandler: stored avatar for %s (%d bytes, %s)", firebaseUID, fileHeader.Size, contentType)

	return c.JSON(fiber.Map{
		"message":   "Photo updated successfully",
		"photo_url": path,
	})
}

// GetPhoto handles GET /api/users/:firebase_uid/photo
func (h *PhotoHandler) GetPhoto(c *fiber.Ctx) error {
	firebaseUID := c.Params("firebase_uid")
	if firebaseUID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid is required"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	stream, err := h.bucket.OpenDownloadStreamByName(ctx, firebaseUID)
	if err != nil {
		if errors.Is(err, mongo.ErrFileNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "No photo for this user"})
		}
		log.Printf("PhotoHandler: download failed for %s: %v", firebaseUID, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to read photo"})
	}
	defer stream.Close()

	contentType := "image/jpeg"
	if meta := stream.GetFile().Metadata; len(meta) > 0 {
		var m struct {
			ContentType string `bson:"content_type"`
		}
		if err := bson.Unmarshal(meta, &m); err == nil && m.ContentType != "" {
			contentType = m.ContentType
		}
	}

	data, err := io.ReadAll(stream)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to read photo"})
	}

	c.Set(fiber.HeaderContentType, contentType)
	// The path is stable across replacements, so the client cache-busts with a
	// query parameter instead of us promising freshness here.
	c.Set(fiber.HeaderCacheControl, "no-cache")
	return c.Send(data)
}

// DeletePhoto handles DELETE /api/users/:firebase_uid/photo
func (h *PhotoHandler) DeletePhoto(c *fiber.Ctx) error {
	firebaseUID := c.Params("firebase_uid")
	if firebaseUID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid is required"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	h.deleteExisting(ctx, firebaseUID)

	if _, err := h.users.UpdateOne(ctx,
		bson.M{"firebase_uid": firebaseUID},
		bson.M{"$set": bson.M{"photo_url": "", "updated_at": time.Now()}},
	); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to update profile"})
	}

	return c.JSON(fiber.Map{"message": "Photo removed"})
}
