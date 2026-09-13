package models

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// Transaction represents a MongoDB document in the transactions collection
type Transaction struct {
	ID              bson.ObjectID `bson:"_id,omitempty" json:"id"`
	UserID          string        `bson:"user_id" json:"user_id"`
	Merchant        string        `bson:"merchant" json:"merchant"`
	Amount          int64         `bson:"amount" json:"amount"`
	Type            string        `bson:"type" json:"type"`
	Category        string        `bson:"category" json:"category"`
	Source          string        `bson:"source" json:"source"`
	ReceiptImageURL string        `bson:"receipt_image_url" json:"receipt_image_url"`
	Date            time.Time     `bson:"date" json:"date"`
	CreatedAt       time.Time     `bson:"created_at" json:"created_at"`
	UpdatedAt       time.Time     `bson:"updated_at" json:"updated_at"`
}

// CreateTransactionRequest represents the API request body when creating a transaction
type CreateTransactionRequest struct {
	Merchant string `json:"merchant"`
	Amount   int64  `json:"amount"`
	Type     string `json:"type"`
	Category string `json:"category"`
	Source   string `json:"source"`
	Date     string `json:"date"`
}

// UpdateTransactionRequest represents the API request body when editing a transaction
type UpdateTransactionRequest struct {
	Merchant *string `json:"merchant"`
	Amount   *int64  `json:"amount"`
	Type     *string `json:"type"`
	Category *string `json:"category"`
	Source   *string `json:"source"`
	Date     *string `json:"date"`
}

// TransactionResponse is what we send back to Flutter
type TransactionResponse struct {
	Transaction     `bson:",inline"` // Embedded fields from Transaction
	FormattedAmount string           `json:"formatted_amount"`
	FormattedDate   string           `json:"formatted_date"`
}
