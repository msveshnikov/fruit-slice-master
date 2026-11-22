const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const menu = document.getElementById('menu');
const scoreElement = document.getElementById('score');
const comboElement = document.getElementById('combo');
const timerElement = document.getElementById('timer');
const startBtn = document.getElementById('startBtn');
const zenModeBtn = document.getElementById('zenModeBtn');
const sliceSound = document.getElementById('sliceSound');
const goldenSliceSound = document.getElementById('goldenSliceSound');
const diamondSliceSound = document.getElementById('diamondSliceSound');
const powerupSound = document.getElementById('powerupSound');
const seasonalFruitDisplay = document.getElementById('seasonalFruitDisplay');
const powerupsContainer = document.getElementById('powerups');
const achievementsContainer = document.getElementById('achievements');

let gameStarted = false;
let isZenMode = false;
let score = 0;
let combo = 1;
let lastSliceTime = 0;
let fruits = [];
let gameTime = 0;
let difficulty = 1;
let hasGoldenBlade = false;
let hasDiamondBlade = false;
let activePowerups = [];
let rareFruits = ['🌈', '💫', '✨', '🥭', '🍏', '🍋‍🟩', '🍋', '🍈'];
let collectedRareFruits = new Set();
let blade = {
    positions: [],
    width: 3,
    color: '#fff',
    fadeTime: 100,
    radius: 30
};

const seasonalFruits = {
    0: '🎊',
    1: '💘',
    2: '🌸',
    3: '🌺',
    4: '🌻',
    5: '🏖️',
    6: '🌞',
    7: '🌴',
    8: '🍁',
    9: '🎃',
    10: '🦃',
    11: '🎄'
};

const powerups = [
    { name: 'Double Points', duration: 10000, emoji: '⚡' },
    { name: 'Slow Motion', duration: 8000, emoji: '⏰' },
    { name: 'Giant Blade', duration: 12000, emoji: '🗡️' }
];

class FruitCollection {
    addFruit(fruit) {
        if (rareFruits.includes(fruit)) {
            collectedRareFruits.add(fruit);
            this.showCollectionNotification(fruit);
        }
    }

    showCollectionNotification(fruit) {
        const notification = document.createElement('div');
        notification.className = 'achievement-popup';
        notification.innerHTML = `Rare Fruit Collected: ${fruit}`;
        document.body.appendChild(notification);
        updateAchievements('collect', collectedRareFruits.size);
        setTimeout(() => notification.remove(), 2000);
    }
}

const fruitCollection = new FruitCollection();

function updateAchievementsDisplay() {
    achievementsContainer.innerHTML = Object.values(achievements)
        .map(
            (a) =>
                `${a.completed ? '✅' : '❌'} ${a.name}: ${Math.min(Math.round(a.progress), a.target)}/${a.target}`
        )
        .join('<br>');
}

function spawnPowerup() {
    if (Math.random() < 0.05 && !isZenMode) {
        const powerup = powerups[Math.floor(Math.random() * powerups.length)];
        activePowerups.push({
            ...powerup,
            x: Math.random() * (canvas.width - 50),
            y: canvas.height,
            speedY: -8,
            active: false
        });
    }
}

function updatePowerups() {
    activePowerups = activePowerups.filter((powerup) => {
        if (!powerup.active) {
            powerup.y += powerup.speedY;
            powerup.speedY += 0.2;
            return powerup.y < canvas.height;
        }
        return Date.now() - powerup.startTime < powerup.duration;
    });
}

function drawPowerups() {
    activePowerups.forEach((powerup) => {
        if (!powerup.active) {
            ctx.font = '30px Arial';
            ctx.fillStyle = '#fff';
            ctx.fillText(powerup.emoji, powerup.x, powerup.y);
        }
    });
}

function checkPowerupCollision(x, y) {
    activePowerups.forEach((powerup) => {
        if (!powerup.active && Math.abs(x - powerup.x) < 30 && Math.abs(y - powerup.y) < 30) {
            powerup.active = true;
            powerup.startTime = Date.now();
            powerupSound.currentTime = 0;
            powerupSound.play();
            showPowerupIndicator(powerup);
        }
    });
}

function showPowerupIndicator(powerup) {
    const indicator = document.createElement('div');
    indicator.className = 'powerup';
    indicator.textContent = `${powerup.emoji} ${powerup.name}`;
    powerupsContainer.appendChild(indicator);

    const duration = powerup.duration;
    const startTime = Date.now();

    function updateTime() {
        const remaining = duration - (Date.now() - startTime);
        if (remaining > 0) {
            indicator.textContent = `${powerup.emoji} ${powerup.name} (${Math.ceil(remaining / 1000)}s)`;
            requestAnimationFrame(updateTime);
        } else {
            indicator.remove();
        }
    }
    updateTime();
}

function updateSeasonalFruit() {
    const month = new Date().getMonth();
    seasonalFruitDisplay.textContent = seasonalFruits[month];
    return seasonalFruits[month];
}

function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}

const fruitTypes = [
    { emoji: '🍎', name: 'apple', color: '#ff6b6b', points: 10 },
    { emoji: '🍊', name: 'orange', color: '#ffa502', points: 15 },
    { emoji: '🍉', name: 'watermelon', color: '#ff4757', points: 20 },
    { emoji: '🍍', name: 'pineapple', color: '#ffd32a', points: 25 },
    { emoji: '🍌', name: 'banana', color: '#ffe066', points: 15 },
    { emoji: '🍐', name: 'pear', color: '#badc58', points: 15 },
    { emoji: '🥝', name: 'kiwi', color: '#6ab04c', points: 20 },
    { emoji: '🍇', name: 'grapes', color: '#5f27cd', points: 20 },
    { emoji: updateSeasonalFruit(), name: 'seasonal', color: '#e056fd', points: 50 }
];

function spawnRareFruit() {
    if (Math.random() < 0.1) {
        const rareFruit = {
            emoji: rareFruits[Math.floor(Math.random() * rareFruits.length)],
            name: 'rare',
            color: '#ffd700',
            points: 100
        };
        const fruit = new Fruit();
        fruit.type = rareFruit;
        fruit.toRemove = true;
        fruits.push(fruit);
    }
}

function updateSeasonalFruit() {
    const month = new Date().getMonth();
    seasonalFruitDisplay.textContent = seasonalFruits[month];
    return seasonalFruits[month];
}

class Fruit {
    constructor() {
        this.reset();
        this.y = canvas.height + 50;
    }

    reset() {
        this.x = Math.random() * canvas.width;
        this.y = canvas.height + 50;
        this.speedX = (Math.random() - 0.5) * 8;
        this.speedY = -15 - Math.random() * 5 * difficulty;
        this.gravity = 0.4;
        this.rotation = Math.random() * Math.PI * 2;
        this.rotationSpeed = (Math.random() - 0.5) * 0.2;
        this.size = 60;
        this.type = fruitTypes[Math.floor(Math.random() * fruitTypes.length)];
        this.sliced = false;
        this.fadeOut = 1;
        this.slicedAngle = 0;
        this.missed = false;
    }

    update() {
        const slowMotion = activePowerups.some((p) => p.active && p.name === 'Slow Motion');
        const speedMultiplier = slowMotion ? 0.5 : 1;

        if (!this.sliced) {
            this.speedY += this.gravity * speedMultiplier;
            this.x += this.speedX * speedMultiplier;
            this.y += this.speedY * speedMultiplier;
            this.rotation += this.rotationSpeed * speedMultiplier;

            if (this.y > canvas.height + 100 && !this.missed && !isZenMode) {
                this.missed = true;
                updateScore(-50);
                combo = 1;
                comboElement.textContent = `Combo: x${combo}`;
                showScorePopup(this.x, this.y, -50);
            }
        } else {
            this.fadeOut -= 0.02 * speedMultiplier;
            this.x += this.speedX * 1.5 * speedMultiplier;
            this.y += this.speedY * 1.5 * speedMultiplier;
            this.speedY += this.gravity * speedMultiplier;
        }

        if (this.y > canvas.height + 100 || this.fadeOut <= 0) {
            this.reset();
        }
    }

    draw() {
        ctx.save();
        ctx.translate(this.x, this.y);
        ctx.rotate(this.rotation);
        ctx.globalAlpha = this.fadeOut;

        if (!this.sliced) {
            ctx.font = `${this.size}px Arial`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(this.type.emoji, 0, 0);
        } else {
            ctx.font = `${this.size}px Arial`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';

            ctx.save();
            ctx.translate(-15, -15);
            ctx.rotate(0.2);
            ctx.fillText(this.type.emoji, 0, 0);
            ctx.restore();

            ctx.save();
            ctx.translate(15, 15);
            ctx.rotate(-0.2);
            ctx.fillText(this.type.emoji, 0, 0);
            ctx.restore();
        }

        ctx.restore();
    }

    checkSlice(x, y) {
        if (this.sliced || this.missed) return false;
        const distance = Math.sqrt((this.x - x) ** 2 + (this.y - y) ** 2);
        const giantBlade = activePowerups.some((p) => p.active && p.name === 'Giant Blade');
        const hitRadius = giantBlade ? this.size * 1.5 : this.size;

        if (distance < hitRadius) {
            this.sliced = true;
            this.slicedAngle = Math.atan2(y - this.y, x - this.x);
            updateAchievements('slice', 1);
            fruitCollection.addFruit(this.type.emoji);
            if (this.toRemove) {
                fruits.pop(this);
            }

            if (hasDiamondBlade) {
                diamondSliceSound.currentTime = 0;
                diamondSliceSound.play();
            } else if (hasGoldenBlade) {
                goldenSliceSound.currentTime = 0;
                goldenSliceSound.play();
            } else {
                sliceSound.currentTime = 0;
                sliceSound.play();
            }

            const now = Date.now();
            if (now - lastSliceTime < 500) {
                combo++;
                updateAchievements('combo', combo);
            } else {
                combo = 1;
            }
            lastSliceTime = now;

            comboElement.textContent = `Combo: x${combo}`;
            let multiplier = 1;
            if (hasDiamondBlade) multiplier = 4;
            else if (hasGoldenBlade) multiplier = 2;

            const doublePoints = activePowerups.some((p) => p.active && p.name === 'Double Points');
            if (doublePoints) multiplier *= 2;

            const points = this.type.points * combo * multiplier;
            updateScore(points);
            showScorePopup(this.x, this.y, points);
            return true;
        }
        return false;
    }
}

function showScorePopup(x, y, points) {
    const popup = document.createElement('div');
    popup.className = 'score-popup';
    popup.style.left = `${x}px`;
    popup.style.top = `${y}px`;
    popup.textContent = points > 0 ? `+${points}` : points;
    document.body.appendChild(popup);
    setTimeout(() => popup.remove(), 1000);
}

function updateScore(points) {
    score += points;
    scoreElement.textContent = `Score: ${score}`;
    updateAchievements('score', score);

    if (score >= 50000 && !hasDiamondBlade) {
        hasDiamondBlade = true;
        blade.color = '#00ffff';
        blade.width = 7;
    } else if (score >= 10000 && !hasGoldenBlade && !hasDiamondBlade) {
        hasGoldenBlade = true;
        blade.color = '#ffd700';
        blade.width = 5;
    }

    if (score >= 50000) {
        document.body.style.backgroundImage = "url('board2.jpg')";
    }
    if (score >= 100000) {
        document.body.style.backgroundImage = "url('board3.jpg')";
    }
}

let particles = [];

function createParticles(x, y, color) {
    const particles = [];
    for (let i = 0; i < 10; i++) {
        particles.push({
            x: x,
            y: y,
            speedX: (Math.random() - 0.5) * 10,
            speedY: (Math.random() - 0.5) * 10,
            size: Math.random() * 4 + 2,
            color: hasDiamondBlade ? '#00ffff' : hasGoldenBlade ? '#ffd700' : color,
            life: 1
        });
    }
    return particles;
}

function updateParticles() {
    for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i];
        p.x += p.speedX;
        p.y += p.speedY;
        p.life -= 0.02;

        if (p.life <= 0) {
            particles.splice(i, 1);
        }
    }
}

function drawParticles() {
    particles.forEach((p) => {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fillStyle = p.color;
        ctx.globalAlpha = p.life;
        ctx.fill();
        ctx.globalAlpha = 1;
    });
}

function startGame(zenMode = false) {
    gameStarted = true;
    isZenMode = zenMode;
    score = 0;
    combo = 1;
    difficulty = 1;
    gameTime = 0;
    hasGoldenBlade = false;
    hasDiamondBlade = false;
    blade.color = '#fff';
    blade.width = 3;
    scoreElement.textContent = `Score: ${score}`;
    comboElement.textContent = `Combo: x${combo}`;
    menu.style.display = 'none';
    fruits = Array(6)
        .fill(null)
        .map(() => new Fruit());
    activePowerups = [];
    powerupsContainer.innerHTML = '';

    if (!zenMode) {
        timerElement.style.display = 'block';
        gameLoop();
    } else {
        timerElement.style.display = 'none';
        gameLoop();
    }

    animate();
    updateAchievementsDisplay();
}

function gameLoop() {
    if (!gameStarted) return;

    gameTime++;
    difficulty = 1 + Math.floor(gameTime / 1000) * 0.2;

    if (gameTime % 60 === 0) {
        const minutes = Math.floor(gameTime / 3600);
        const seconds = Math.floor((gameTime % 3600) / 60);
        timerElement.textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;
        spawnPowerup();
        spawnRareFruit();
    }

    if (isZenMode) {
        updateAchievements('zen', 1 / 60);
    }

    setTimeout(gameLoop, 1000 / 60);
}

function handleTouch(e) {
    if (!gameStarted) return;
    e.preventDefault();
    const touch = e.touches[0];
    const rect = canvas.getBoundingClientRect();
    const x = touch.clientX - rect.left;
    const y = touch.clientY - rect.top;

    blade.positions.push({ x, y, time: Date.now() });

    fruits.forEach((fruit) => {
        if (fruit.checkSlice(x, y)) {
            particles = particles.concat(createParticles(fruit.x, fruit.y, fruit.type.color));
        }
    });

    checkPowerupCollision(x, y);

    if (blade.positions.length > 10) {
        blade.positions.shift();
    }
}

function drawBlade() {
    if (blade.positions.length < 2) return;

    ctx.beginPath();
    ctx.moveTo(blade.positions[0].x, blade.positions[0].y);

    for (let i = 1; i < blade.positions.length; i++) {
        const p = blade.positions[i];
        ctx.lineTo(p.x, p.y);
    }

    ctx.strokeStyle = blade.color;
    ctx.lineWidth = blade.width;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.shadowColor = blade.color;
    ctx.shadowBlur = 20;
    ctx.stroke();
    ctx.shadowBlur = 0;

    const now = Date.now();
    blade.positions = blade.positions.filter((p) => now - p.time < blade.fadeTime);
}

function animate() {
    if (!gameStarted) return;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    fruits.forEach((fruit) => {
        fruit.update();
        fruit.draw();
    });

    updatePowerups();
    drawPowerups();
    updateParticles();
    drawParticles();
    drawBlade();
    updateAchievementsDisplay();

    requestAnimationFrame(animate);
}

resizeCanvas();
window.addEventListener('resize', resizeCanvas);
startBtn.addEventListener('click', () => startGame(false));
zenModeBtn.addEventListener('click', () => startGame(true));
canvas.addEventListener('touchmove', handleTouch);
canvas.addEventListener('touchstart', handleTouch);

fetch('https://allchat.online/api/fruit/score')
    .then((response) => response.json())
    .then((data) => {
        topScores = data;
        updateTopScoresDisplay();
    })
    .catch(() => {});
