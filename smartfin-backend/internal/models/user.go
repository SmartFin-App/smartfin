package models

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// User represents a MongoDB document in the users collection
type User struct {
	ID              bson.ObjectID `bson:"_id,omitempty" json:"id"`
	FirebaseUID     string             `bson:"firebase_uid" json:"firebase_uid"`
	Name            string             `bson:"name" json:"name"`
	Email           string             `bson:"email" json:"email"`
	PhotoURL        string             `bson:"photo_url" json:"photo_url"`
	MonthlyIncome   int64              `bson:"monthly_income" json:"monthly_income"`
	IncomeBracket   string             `bson:"income_bracket" json:"income_bracket"`
	CurrentStatus   string             `bson:"current_status" json:"current_status"`
	FinancialHealth string             `bson:"financial_health" json:"financial_health"`
	BudgetLimit     int64              `bson:"budget_limit" json:"budget_limit"`
	SavingsGoal     int64              `bson:"savings_goal,omitempty" json:"savings_goal,omitempty"`
	SavingsGoalName string             `bson:"savings_goal_name,omitempty" json:"savings_goal_name,omitempty"`
	SavingsTargetDate string           `bson:"savings_target_date,omitempty" json:"savings_target_date,omitempty"`
	WellnessScore   int                `bson:"wellness_score" json:"wellness_score"`
	Level           int                `bson:"level" json:"level"`
	CreatedAt       time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt       time.Time          `bson:"updated_at" json:"updated_at"`
}

// CreateUserRequest represents the API request body when creating a user
type CreateUserRequest struct {
	FirebaseUID     string  `json:"firebase_uid"`
	Name            string  `json:"name"`
	Email           string  `json:"email"`
	PhotoURL        string  `json:"photo_url"`
	MonthlyIncome   int64   `json:"monthly_income"`
	IncomeBracket   string  `json:"income_bracket"`
	CurrentStatus   string  `json:"current_status"`
	FinancialHealth string  `json:"financial_health"`
	BudgetLimit     int64   `json:"budget_limit"`
}
