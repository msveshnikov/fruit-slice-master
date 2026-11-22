# Fruit Slice Master - Game Documentation

## Overview

This is the main HTML file (`www/index.html`) for the Fruit Slice Master game, a mobile-friendly web
game where players slice fruits by swiping across the screen. The game features both Arcade and Zen
modes, power-ups, combo systems, and seasonal fruits.

## Core Components

### 1. Game Setup and Configuration

#### Canvas Setup

```javascript
const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
```

Creates and initializes the game canvas where all rendering occurs.

#### Game States

```javascript
let gameStarted = false;
let isZenMode = false;
let score = 0;
let combo = 1;
```

Manages core game state variables.

### 2. Game Features

#### Fruit Types

```javascript
const fruitTypes = [
    { emoji: '🍎', name: 'apple', color: '#ff6b6b', points: 10 }
    // ... other fruits
];
```

Defines available fruits with their properties.

#### Power-ups

```javascript
const powerups = [
    { name: 'Double Points', duration: 10000, emoji: '⚡' },
    { name: 'Slow Motion', duration: 8000, emoji: '⏰' },
    { name: 'Giant Blade', duration: 12000, emoji: '🗡️' }
];
```

### 3. Core Classes

#### Fruit Class

```javascript
class Fruit {
    constructor()
    reset()
    update()
    draw()
    checkSlice(x, y)
}
```

**Methods:**

-   `constructor()`: Initializes a new fruit instance
-   `reset()`: Resets fruit position and properties
-   `update()`: Updates fruit physics and position
-   `draw()`: Renders fruit on canvas
-   `checkSlice(x, y)`: Checks if fruit is sliced at coordinates

### 4. Key Functions

#### Game Control

```javascript
function startGame(zenMode = false)
```

**Parameters:**

-   `zenMode`: Boolean indicating if game should start in Zen mode

#### Score Management

```javascript
function updateScore(points)
```

**Parameters:**

-   `points`: Number of points to add/subtract

#### Particle Effects

```javascript
function createParticles(x, y, color)
```

**Parameters:**

-   `x`: X coordinate
-   `y`: Y coordinate
-   `color`: Particle color

### 5. Event Handling

```javascript
function handleTouch(e)
```

Handles touch events for fruit slicing.

### 6. Network Features

```javascript
async function updateScore()
```

Sends score updates to server at `allchat.online/api/fruit/score`.

## CSS Styling

### Key Styles

-   Responsive layout with fluid dimensions
-   Game UI elements (score, combo, timer)
-   Menu and button styling
-   Animation effects for power-ups and score popups

## Integration Points

### Server Communication

-   Score updates to backend
-   Leaderboard fetching
-   Country-based player tracking

### Assets

-   Sound effects for different blade types
-   Seasonal fruit emojis
-   Power-up indicators

## Usage Example

```javascript
// Start arcade mode game
startGame(false);

// Start zen mode game
startGame(true);

// Update score
updateScore(100);

// Create slice effect
createParticles(100, 100, '#ff0000');
```

## Project Context

This file serves as the main game interface in the Cordova-based mobile application. It interacts
with the server component (`server/fruit.js`) for score tracking and leaderboards.

## Dependencies

-   Google Analytics
-   External sound assets
-   Backend API endpoints for score tracking

## Browser Compatibility

-   Optimized for mobile browsers
-   Touch event support required
-   Modern CSS features utilized

This documentation provides an overview of the main game file. For complete project documentation,
refer to additional files in the `docs` directory.
