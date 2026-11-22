# Fruit Game Server Documentation

## Overview

`fruit.js` is the main server file for the Fruit Game application, providing an Express.js-based API
to handle game scores and leaderboards. The server maintains a persistent score system using a JSON
file and offers endpoints for submitting scores and retrieving top performers.

## Server Configuration

-   **Port**: Runs on port 3000 by default (configurable via environment variable `PORT`)
-   **CORS**: Enabled for all origins
-   **Data Storage**: Uses `scores.json` for persistent storage

## Core Functions

### `initScoresFile()`

Initializes the scores storage file.

```javascript
async function initScoresFile()
```

-   **Description**: Creates `scores.json` if it doesn't exist
-   **Returns**: Promise<void>
-   **Usage Example**:

```javascript
await initScoresFile();
```

### `updateScores(countryCode, countryName, score)`

Updates the score for a specific country.

```javascript
async function updateScores(countryCode, countryName, score)
```

-   **Parameters**:
    -   `countryCode` (string): Two-letter country code
    -   `countryName` (string): Full country name
    -   `score` (number): Player's score
-   **Behavior**: Updates score only if it's higher than the existing score
-   **Usage Example**:

```javascript
await updateScores('US', 'United States', 1000);
```

### `countryCodeToFlag(code)`

Converts a country code to a flag emoji.

```javascript
function countryCodeToFlag(code)
```

-   **Parameters**:
    -   `code` (string): Two-letter country code
-   **Returns**: String (flag emoji)
-   **Usage Example**:

```javascript
const flag = countryCodeToFlag('US'); // 🇺🇸
```

### `getTop3Countries()`

Retrieves the top 3 scoring countries.

```javascript
async function getTop3Countries()
```

-   **Returns**: Promise<Array> of objects containing:
    -   `countryCode`: Two-letter country code
    -   `countryName`: Full country name
    -   `score`: Numeric score
    -   `flag`: Country flag emoji
-   **Usage Example**:

```javascript
const topThree = await getTop3Countries();
```

## API Endpoints

### POST `/api/fruit/score`

Submits a new score.

-   **Method**: POST
-   **Headers**:
    -   `geoip_country_code`: Two-letter country code
    -   `geoip_country_name`: Full country name
-   **Body**:
    ```json
    {
      "score": number
    }
    ```
-   **Response**:
    ```json
    {
        "success": true
    }
    ```
-   **Error Codes**:
    -   400: Missing required data
    -   500: Server error

### GET `/api/fruit/top`

Retrieves top 3 scoring countries.

-   **Method**: GET
-   **Response**:
    ```json
    [
        {
            "countryCode": "US",
            "countryName": "United States",
            "score": 1000,
            "flag": "🇺🇸"
        }
        // ... up to 3 entries
    ]
    ```
-   **Error Codes**:
    -   500: Server error

## Project Integration

This server component is part of a larger project structure:

-   Located in `/server/fruit.js`
-   Serves as the backend for the web application in `/www`
-   Supports the game functionality described in `/docs`

## Dependencies

-   express
-   fs (Node.js built-in)
-   path (Node.js built-in)
-   cors
-   url (Node.js built-in)

## Error Handling

The server implements basic error handling for:

-   File system operations
-   Missing or invalid request data
-   Server-side errors

## Security Considerations

-   CORS is configured to accept requests from all origins (`*`)
-   Input validation is performed for score submissions
-   No authentication mechanism is implemented (consider adding if needed)

## Data Persistence

Scores are stored in `scores.json` with the following structure:

```json
{
    "countryCode": {
        "name": "Country Name",
        "score": 1000,
        "timestamp": 1234567890
    }
}
```

This documentation provides a comprehensive overview of the server implementation for the Fruit Game
application. For additional details about the game itself, refer to the documentation in the `/docs`
directory.
