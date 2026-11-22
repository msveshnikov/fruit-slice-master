window.dataLayer = window.dataLayer || [];
function gtag() {
    dataLayer.push(arguments);
}
gtag('js', new Date());
gtag('config', 'G-L4KLPWXQ75');

let lastScore = 0;
let topScores = [];
let achievements = JSON.parse(localStorage.getItem('achievements2')) || {
    fruitNinja: {
        name: 'Fruit Ninja',
        description: 'Slice 1000 fruits',
        progress: 0,
        target: 1000,
        completed: false
    },
    comboMaster: {
        name: 'Combo Master',
        description: 'Reach 10x combo',
        progress: 0,
        target: 10,
        completed: false
    },
    highScorer: {
        name: 'High Scorer',
        description: 'Score 50000 points',
        progress: 0,
        target: 50000,
        completed: false
    },
    zenMaster: {
        name: 'Zen Master',
        description: 'Play Zen mode for 10 minutes',
        progress: 0,
        target: 600,
        completed: false
    },
    collector: {
        name: 'Fruit Collector',
        description: 'Collect all rare fruits',
        progress: 0,
        target: 8,
        completed: false
    },
    grandMaster: {
        name: 'Grand Master',
        description: 'Score 100000 points',
        progress: 0,
        target: 100000,
        completed: false
    },
    legend: {
        name: 'Fruit Legend',
        description: 'Score 500000 points',
        progress: 0,
        target: 500000,
        completed: false
    }
};

function updateAchievements(type, value) {
    switch (type) {
        case 'slice':
            achievements.fruitNinja.progress += value;
            break;
        case 'combo':
            achievements.comboMaster.progress = Math.max(achievements.comboMaster.progress, value);
            break;
        case 'score':
            achievements.highScorer.progress = Math.max(achievements.highScorer.progress, value);
            achievements.grandMaster.progress = Math.max(achievements.grandMaster.progress, value);
            achievements.legend.progress = Math.max(achievements.legend.progress, value);
            break;
        case 'zen':
            achievements.zenMaster.progress += value;
            break;
        case 'collect':
            achievements.collector.progress = value;
            break;
    }

    Object.values(achievements).forEach((achievement) => {
        if (!achievement.completed && achievement.progress >= achievement.target) {
            achievement.completed = true;
            showAchievementUnlock(achievement);
        }
    });

    localStorage.setItem('achievements2', JSON.stringify(achievements));
}

function showAchievementUnlock(achievement) {
    const popup = document.createElement('div');
    popup.className = 'achievement-popup';
    popup.innerHTML = `
        <h3>🏆 Achievement Unlocked!</h3>
        <p>${achievement.name}</p>
        <p>${achievement.description}</p>
    `;
    document.body.appendChild(popup);
    setTimeout(() => popup.remove(), 3000);
}

async function updateScore() {
    if (lastScore !== score && !isZenMode) {
        try {
            const response = await fetch('https://allchat.online/api/fruit/score', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ score })
            });
            lastScore = score;
            updateAchievements('score', score);
        } catch (error) {
            console.error(error);
        }
    }
}

setInterval(updateScore, 10000);
checkDailyReward();

function updateTopScoresDisplay() {
    const topScoresElement = document.getElementById('topScores');
    if (topScoresElement && topScores.length) {
        topScoresElement.innerHTML = topScores
            .map(
                (score, index) =>
                    `${index + 1}. ${score.countryName} ${score.flag || ''}: ${score.score}`
            )
            .join('<br>');
    }
}
