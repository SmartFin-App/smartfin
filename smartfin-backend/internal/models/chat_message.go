package models

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// ChatMessage represents a message stored in the chat_messages collection
type ChatMessage struct {
	ID        bson.ObjectID `bson:"_id,omitempty" json:"id"`
	UserID    string        `bson:"user_id" json:"user_id"`
	Role      string        `bson:"role" json:"role"` // "user", "model", "tool"
	Content   string        `bson:"content" json:"content"`
	ToolCalls []string      `bson:"tool_calls,omitempty" json:"tool_calls,omitempty"`
	CreatedAt time.Time     `bson:"created_at" json:"created_at"`
}
