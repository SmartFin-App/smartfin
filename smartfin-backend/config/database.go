package config

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/joho/godotenv"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
	"go.mongodb.org/mongo-driver/v2/mongo/readpref"
)

var (
	// Client holds the MongoDB client instance
	Client *mongo.Client

	// DB holds the specific database instance
	DB *mongo.Database
)

// ConnectDB initializes the database connection
func ConnectDB() {
	// Load .env file
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: Error loading .env file (might be using system env variables)")
	}

	// Get environment variables
	mongoURI := os.Getenv("MONGODB_URI")
	if mongoURI == "" {
		log.Fatal("MONGODB_URI environment variable is not set")
	}

	dbName := os.Getenv("DB_NAME")
	if dbName == "" {
		log.Fatal("DB_NAME environment variable is not set")
	}

	// Create a context with a 25-second timeout for initial cloud connection
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	// Create MongoDB client options and connect
	clientOptions := options.Client().ApplyURI(mongoURI)
	client, err := mongo.Connect(clientOptions)
	if err != nil {
		log.Fatal("Failed to connect to MongoDB: ", err)
	}

	// Ping the database to confirm the connection works
	err = client.Ping(ctx, readpref.Primary())
	if err != nil {
		log.Fatal("Failed to ping MongoDB: ", err)
	}

	// Assign the global client and database
	Client = client
	DB = Client.Database(dbName)

	log.Println("Connected to MongoDB!")
}

// GetCollection returns a MongoDB collection by name
func GetCollection(name string) *mongo.Collection {
	return DB.Collection(name)
}
