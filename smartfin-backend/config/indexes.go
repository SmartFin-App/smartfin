package config

import (
	"context"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// indexSpec pairs an index with the query it exists to serve, so the reason for
// each one survives in the code rather than only in someone's memory.
type indexSpec struct {
	collection string
	model      mongo.IndexModel
	serves     string
}

// requiredIndexes are the indexes the app's read paths depend on.
//
// Every user-scoped query filters on the Firebase UID and then sorts — by date
// for transactions, by created_at for the coach transcript. Without a compound
// index on exactly that pair, MongoDB scans the collection and sorts in memory,
// which is also the retrieval cost that sits inside the coach's 45s budget.
//
// The equality field comes first and the sort field second: that ordering lets a
// single index satisfy both the filter and the sort (the ESR rule — Equality,
// Sort, Range).
var requiredIndexes = []indexSpec{
	{
		collection: "users",
		model: mongo.IndexModel{
			Keys:    bson.D{{Key: "firebase_uid", Value: 1}},
			Options: options.Index().SetName("firebase_uid_1"),
		},
		serves: "every profile lookup — the orchestrator's system prompt, the retrieval agent, and all user endpoints",
	},
	{
		collection: "transactions",
		model: mongo.IndexModel{
			Keys:    bson.D{{Key: "user_id", Value: 1}, {Key: "date", Value: -1}},
			Options: options.Index().SetName("user_id_1_date_-1"),
		},
		serves: "get_transactions, the month-window scans behind get_budget_summary, and the filtered history list",
	},
	{
		collection: "monthly_summaries",
		model: mongo.IndexModel{
			Keys:    bson.D{{Key: "user_id", Value: 1}, {Key: "month", Value: 1}},
			Options: options.Index().SetName("user_id_1_month_1"),
		},
		serves: "GetOrCreateSummary lookups and cache invalidation on every transaction write",
	},
	{
		collection: "chat_messages",
		model: mongo.IndexModel{
			Keys:    bson.D{{Key: "user_id", Value: 1}, {Key: "created_at", Value: -1}},
			Options: options.Index().SetName("user_id_1_created_at_-1"),
		},
		serves: "get_recent_conversations and the coach history endpoint",
	},
}

// EnsureIndexes creates the indexes above if they do not already exist.
//
// Creating an index that already exists with the same keys and name is a no-op,
// so this is safe to run on every start. Failures are logged and skipped rather
// than fatal: a missing index makes queries slower, not wrong, and is never a
// reason to refuse to serve.
func EnsureIndexes(ctx context.Context) {
	if DB == nil {
		log.Println("Warning: EnsureIndexes called before the database was connected")
		return
	}

	created := 0
	for _, spec := range requiredIndexes {
		specCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
		name, err := DB.Collection(spec.collection).Indexes().CreateOne(specCtx, spec.model)
		cancel()

		if err != nil {
			log.Printf("Warning: could not create index on %s (%s): %v",
				spec.collection, spec.serves, err)
			continue
		}
		created++
		log.Printf("Index ready: %s.%s", spec.collection, name)
	}

	log.Printf("Indexes verified: %d/%d", created, len(requiredIndexes))
}
