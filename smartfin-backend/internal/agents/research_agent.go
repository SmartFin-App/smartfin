package agents

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

// ResearchAgent gathers external financial knowledge via web search
type ResearchAgent struct {
	httpClient *http.Client
}

// NewResearchAgent creates a new FinancialResearchAgent
func NewResearchAgent() *ResearchAgent {
	return &ResearchAgent{
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// SearchResult represents a single search item
type SearchResult struct {
	Title   string `json:"title"`
	Snippet string `json:"snippet"`
	URL     string `json:"url"`
}

// WebSearch executes a web search for market, financial, or regulatory data
func (a *ResearchAgent) WebSearch(ctx context.Context, query string) (map[string]any, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return map[string]any{
			"query":   query,
			"results": []any{},
			"summary": "No query provided for web search.",
		}, nil
	}

	log.Printf("ResearchAgent: executing web search for: %s", query)

	// Check if custom SerpAPI or search key exists
	if apiKey := os.Getenv("SERPAPI_API_KEY"); apiKey != "" {
		results, err := a.searchSerpAPI(ctx, query, apiKey)
		if err == nil && len(results) > 0 {
			return map[string]any{
				"query":   query,
				"source":  "Google Search (SerpAPI)",
				"results": results,
			}, nil
		}
	}

	// Primary search: DuckDuckGo HTML search
	results, err := a.searchDuckDuckGo(ctx, query)
	if err == nil && len(results) > 0 {
		return map[string]any{
			"query":   query,
			"source":  "Web Search",
			"results": results,
		}, nil
	}

	log.Printf("ResearchAgent: web search unavailable for: %s", query)
	return searchUnavailable(query), nil
}

// searchUnavailable is what the coach receives when no search backend answered.
//
// It carries no figures on purpose. This used to return a canned paragraph —
// a 2.50% policy rate, savings rates, inflation, tax allowances — labelled
// "Financial Knowledge Base", and the model could not tell it from a live
// result: it told users the policy rate was "currently 2.50% (as of mid-2026)",
// a hardcoded number with a date the model invented. For rates, prices and
// allowances that change, saying "I couldn't check" is the only honest answer.
func searchUnavailable(query string) map[string]any {
	return map[string]any{
		"query":     query,
		"available": false,
		"source":    "none",
		"results":   []any{},
		"note": "Web search is unavailable right now, so no current information was retrieved. " +
			"Do not state any current rate, price, statistic or tax figure, from memory or otherwise. " +
			"Tell the user you could not check the latest figure, and point them to where to confirm it: " +
			"the bank's own website or app for deposit rates, bot.or.th for the policy rate and inflation, " +
			"rd.go.th for tax allowances.",
	}
}

// searchDuckDuckGo queries DuckDuckGo HTML and extracts clean text snippets
func (a *ResearchAgent) searchDuckDuckGo(ctx context.Context, query string) ([]SearchResult, error) {
	searchURL := "https://html.duckduckgo.com/html/?q=" + url.QueryEscape(query)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, searchURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9,th;q=0.8")

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("duckduckgo search returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	htmlContent := string(body)

	// Extract result blocks
	// Pattern for result title & link
	titleRegex := regexp.MustCompile(`(?s)<a[^>]*class="result__snippet"[^>]*>(.*?)</a>`)
	snippetMatches := titleRegex.FindAllStringSubmatch(htmlContent, 5)

	headerRegex := regexp.MustCompile(`(?s)<a[^>]*class="result__url"[^>]*href="([^"]*)"[^>]*>(.*?)</a>`)
	urlMatches := headerRegex.FindAllStringSubmatch(htmlContent, 5)

	stripTagsRegex := regexp.MustCompile(`<[^>]*>`)

	var results []SearchResult
	for i, sm := range snippetMatches {
		if len(sm) < 2 {
			continue
		}
		rawSnippet := stripTagsRegex.ReplaceAllString(sm[1], "")
		cleanSnippet := strings.TrimSpace(html.UnescapeString(rawSnippet))

		link := ""
		title := query
		if i < len(urlMatches) && len(urlMatches[i]) >= 3 {
			link = strings.TrimSpace(html.UnescapeString(urlMatches[i][1]))
			rawTitle := stripTagsRegex.ReplaceAllString(urlMatches[i][2], "")
			title = strings.TrimSpace(html.UnescapeString(rawTitle))
		}

		if cleanSnippet != "" {
			results = append(results, SearchResult{
				Title:   title,
				Snippet: cleanSnippet,
				URL:     link,
			})
		}
	}

	return results, nil
}

// searchSerpAPI queries SerpAPI if an API key is provided
func (a *ResearchAgent) searchSerpAPI(ctx context.Context, query, apiKey string) ([]SearchResult, error) {
	endpoint := fmt.Sprintf("https://serpapi.com/search.json?q=%s&api_key=%s&hl=en&gl=th", url.QueryEscape(query), apiKey)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var data struct {
		OrganicResults []struct {
			Title   string `json:"title"`
			Snippet string `json:"snippet"`
			Link    string `json:"link"`
		} `json:"organic_results"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, err
	}

	var results []SearchResult
	for _, r := range data.OrganicResults {
		if len(results) >= 4 {
			break
		}
		results = append(results, SearchResult{
			Title:   r.Title,
			Snippet: r.Snippet,
			URL:     r.Link,
		})
	}
	return results, nil
}
