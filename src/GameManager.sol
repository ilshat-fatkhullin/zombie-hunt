// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PlayerRegistry.sol";
import "./CardDeck.sol";
import "./GameMatch.sol";
import "./SpecialCards.sol";

/*
Orchestrates the overall game flow and determines victory conditions:
- Initialize game rounds with 4 teams of 16 players each
- Manage game state (active, completed, cancelled)
- Track overall game progress and determine winners
- Handle team assignments and player registration
*/

enum GameState {
    NOT_STARTED,
    REGISTRATION,
    ACTIVE,
    COMPLETED
}

enum GameResult {
    NOT_DETERMINED,
    TEAM_0_WINS,  // Most humans or zombies on team 0
    TEAM_1_WINS,
    TEAM_2_WINS,
    TEAM_3_WINS,
    DRAW
}

struct Game {
    uint256 gameId;
    GameState state;
    GameResult result;
    uint256 startTime;
    uint256 endTime;
    address[] players;
    uint256[] teams;
    bool cardsDealt;
}

contract GameManager {
    PlayerRegistry public playerRegistry;
    CardDeck public cardDeck;
    GameMatch public gameMatch;
    SpecialCards public specialCards;

    // Game storage
    mapping(uint256 => Game) public games;
    uint256 public gameCounter = 0;
    uint256 public currentGameId = 0;

    // Team tracking for current game
    mapping(uint256 => address[]) public teamPlayers; // team => players
    mapping(address => bool) public registeredInCurrentGame;

    // Constants
    uint256 constant PLAYERS_PER_TEAM = 16;
    uint256 constant NUM_TEAMS = 4;
    uint256 constant TOTAL_PLAYERS = PLAYERS_PER_TEAM * NUM_TEAMS;

    // Events
    event GameCreated(uint256 indexed gameId);
    event GameStarted(uint256 indexed gameId);
    event PlayerRegisteredForGame(uint256 indexed gameId, address indexed player, uint256 team);
    event CardsDealt(uint256 indexed gameId);
    event GameCompleted(uint256 indexed gameId, GameResult result);
    event TeamWon(uint256 indexed gameId, uint256 team);
    event PlayerWonGame(uint256 indexed gameId, address indexed player);

    constructor(address _playerRegistry, address _cardDeck, address _gameMatch, address _specialCards) {
        playerRegistry = PlayerRegistry(_playerRegistry);
        cardDeck = CardDeck(_cardDeck);
        gameMatch = GameMatch(_gameMatch);
        specialCards = SpecialCards(_specialCards);
    }

    // Create a new game
    function createGame() external returns (uint256) {
        uint256 gameId = gameCounter++;
        currentGameId = gameId;

        games[gameId] = Game({
            gameId: gameId,
            state: GameState.REGISTRATION,
            result: GameResult.NOT_DETERMINED,
            startTime: 0,
            endTime: 0,
            players: new address[](0),
            teams: new uint256[](0),
            cardsDealt: false
        });

        emit GameCreated(gameId);
        return gameId;
    }

    // Register a player for the current game
    function registerPlayerForGame(address _player, uint256 _team) external {
        require(_team < NUM_TEAMS, "Invalid team number");
        require(!registeredInCurrentGame[_player], "Player already registered");
        require(teamPlayers[_team].length < PLAYERS_PER_TEAM, "Team is full");

        Game storage game = games[currentGameId];
        require(game.state == GameState.REGISTRATION, "Registration is closed");

        // Register in PlayerRegistry
        playerRegistry.registerPlayer(_player, _team);

        // Add to team
        teamPlayers[_team].push(_player);
        registeredInCurrentGame[_player] = true;

        game.players.push(_player);
        game.teams.push(_team);

        emit PlayerRegisteredForGame(currentGameId, _player, _team);

        // If all teams are full, auto-start the game
        if (
            teamPlayers[0].length == PLAYERS_PER_TEAM &&
            teamPlayers[1].length == PLAYERS_PER_TEAM &&
            teamPlayers[2].length == PLAYERS_PER_TEAM &&
            teamPlayers[3].length == PLAYERS_PER_TEAM
        ) {
            _startGame(currentGameId);
        }
    }

    // Start the game (must have all 64 players registered)
    function startGame() external {
        require(
            teamPlayers[0].length == PLAYERS_PER_TEAM &&
            teamPlayers[1].length == PLAYERS_PER_TEAM &&
            teamPlayers[2].length == PLAYERS_PER_TEAM &&
            teamPlayers[3].length == PLAYERS_PER_TEAM,
            "Not all teams are full"
        );

        _startGame(currentGameId);
    }

    // Internal function to start the game
    function _startGame(uint256 _gameId) private {
        Game storage game = games[_gameId];
        require(game.state == GameState.REGISTRATION, "Game already started");

        game.state = GameState.ACTIVE;
        game.startTime = block.timestamp;

        // Deal initial cards
        address[] memory players = new address[](TOTAL_PLAYERS);
        uint256[] memory teams = new uint256[](TOTAL_PLAYERS);

        uint256 index = 0;
        for (uint256 team = 0; team < NUM_TEAMS; team++) {
            for (uint256 i = 0; i < teamPlayers[team].length; i++) {
                players[index] = teamPlayers[team][i];
                teams[index] = team;
                index++;
            }
        }

        cardDeck.dealInitialCards(players, teams);
        game.cardsDealt = true;

        emit CardsDealt(_gameId);
        emit GameStarted(_gameId);
    }

    // End the game and determine winner
    function endGame() external {
        Game storage game = games[currentGameId];
        require(game.state == GameState.ACTIVE, "Game is not active");

        game.state = GameState.COMPLETED;
        game.endTime = block.timestamp;

        // Determine winner based on zombie vs human count per team
        _determineWinner(currentGameId);

        emit GameCompleted(currentGameId, game.result);
    }

    // Determine winner: team with most players on the winning side (zombies or humans)
    function _determineWinner(uint256 _gameId) private {
        Game storage game = games[_gameId];

        uint256[] memory teamHumanCount = new uint256[](NUM_TEAMS);
        uint256[] memory teamZombieCount = new uint256[](NUM_TEAMS);

        // Count humans and zombies per team
        for (uint256 i = 0; i < game.players.length; i++) {
            address player = game.players[i];
            uint256 team = game.teams[i];
            PlayerStatus status = playerRegistry.getPlayerStatus(player);

            if (status == PlayerStatus.HUMAN) {
                teamHumanCount[team]++;
            } else if (status == PlayerStatus.ZOMBIE) {
                teamZombieCount[team]++;
            }
            // ELIMINATED players are not counted
        }

        // Determine which side wins (zombies vs humans across all teams)
        uint256 totalHumans = teamHumanCount[0] + teamHumanCount[1] + teamHumanCount[2] + teamHumanCount[3];
        uint256 totalZombies = teamZombieCount[0] + teamZombieCount[1] + teamZombieCount[2] + teamZombieCount[3];

        // If zombies outnumber humans, zombies win
        if (totalZombies > totalHumans) {
            // Find team with most zombies
            uint256 maxZombies = 0;
            uint256 winningTeam = 0;
            for (uint256 i = 0; i < NUM_TEAMS; i++) {
                if (teamZombieCount[i] > maxZombies) {
                    maxZombies = teamZombieCount[i];
                    winningTeam = i;
                }
            }
            if (maxZombies > 0) {
                game.result = GameResult(uint8(GameResult.TEAM_0_WINS) + winningTeam);
                emit TeamWon(_gameId, winningTeam);
            } else {
                game.result = GameResult.DRAW;
            }
        } else if (totalHumans > totalZombies) {
            // Find team with most humans
            uint256 maxHumans = 0;
            uint256 winningTeam = 0;
            for (uint256 i = 0; i < NUM_TEAMS; i++) {
                if (teamHumanCount[i] > maxHumans) {
                    maxHumans = teamHumanCount[i];
                    winningTeam = i;
                }
            }
            if (maxHumans > 0) {
                game.result = GameResult(uint8(GameResult.TEAM_0_WINS) + winningTeam);
                emit TeamWon(_gameId, winningTeam);
            } else {
                game.result = GameResult.DRAW;
            }
        } else {
            // Equal humans and zombies = draw
            game.result = GameResult.DRAW;
        }
    }

    // Get game details
    function getGameDetails(uint256 _gameId) external view returns (
        GameState state,
        GameResult result,
        uint256 startTime,
        uint256 endTime,
        uint256 playerCount,
        bool cardsDealt
    ) {
        Game storage game = games[_gameId];
        return (
            game.state,
            game.result,
            game.startTime,
            game.endTime,
            game.players.length,
            game.cardsDealt
        );
    }

    // Get team player count
    function getTeamPlayerCount(uint256 _team) external view returns (uint256) {
        require(_team < NUM_TEAMS, "Invalid team");
        return teamPlayers[_team].length;
    }

    // Get all players in a team
    function getTeamPlayers(uint256 _team) external view returns (address[] memory) {
        require(_team < NUM_TEAMS, "Invalid team");
        return teamPlayers[_team];
    }

    // Get current game state
    function getCurrentGameState() external view returns (GameState) {
        return games[currentGameId].state;
    }

    // Get winning condition status for current game
    function getGameStatus() external view returns (
        uint256 totalHumans,
        uint256 totalZombies,
        uint256 totalEliminated,
        bool zombiesWinning
    ) {
        totalHumans = playerRegistry.countPlayersByStatus(PlayerStatus.HUMAN);
        totalZombies = playerRegistry.countPlayersByStatus(PlayerStatus.ZOMBIE);
        totalEliminated = playerRegistry.countPlayersByStatus(PlayerStatus.ELIMINATED);

        zombiesWinning = totalZombies > totalHumans;
    }

    // Get team status (human/zombie/eliminated count)
    function getTeamStatus(uint256 _team) external view returns (
        uint256 humanCount,
        uint256 zombieCount,
        uint256 eliminatedCount
    ) {
        require(_team < NUM_TEAMS, "Invalid team");

        humanCount = playerRegistry.countTeamPlayersByStatus(_team, PlayerStatus.HUMAN);
        zombieCount = playerRegistry.countTeamPlayersByStatus(_team, PlayerStatus.ZOMBIE);
        eliminatedCount = playerRegistry.countTeamPlayersByStatus(_team, PlayerStatus.ELIMINATED);
    }

    // Check if a player is a winner (on winning team when game ends)
    function isPlayerWinner(address _player) external view returns (bool) {
        Game storage game = games[currentGameId];
        require(game.state == GameState.COMPLETED, "Game not completed");

        // Get player's team
        uint256 playerTeam = playerRegistry.getPlayerTeam(_player);
        GameResult expectedWinner = GameResult(uint8(GameResult.TEAM_0_WINS) + playerTeam);

        return game.result == expectedWinner;
    }

    // Check GAME OVER conditions for a player
    function isPlayerGameOver(address _player) external view returns (bool, string memory) {
        // GAME OVER if zombie and eliminated by shotgun
        if (
            playerRegistry.getPlayerStatus(_player) == PlayerStatus.ELIMINATED &&
            playerRegistry.getPlayerStatus(_player) == PlayerStatus.ZOMBIE
        ) {
            return (true, "Zombie eliminated by shotgun");
        }

        // GAME OVER if player runs out of cards
        if (cardDeck.getCardCount(_player) == 0) {
            return (true, "No cards remaining");
        }

        // GAME OVER if player is on losing side at end of game
        Game storage game = games[currentGameId];
        if (game.state == GameState.COMPLETED) {
            uint256 playerTeam = playerRegistry.getPlayerTeam(_player);
            GameResult expectedWinner = GameResult(uint8(GameResult.TEAM_0_WINS) + playerTeam);
            if (game.result != expectedWinner) {
                return (true, "On losing side");
            }
        }

        return (false, "");
    }

    // Check GAME CLEAR conditions for a player
    function isPlayerGameClear(address _player) external view returns (bool) {
        Game storage game = games[currentGameId];
        if (game.state != GameState.COMPLETED) {
            return false;
        }

        uint256 playerTeam = playerRegistry.getPlayerTeam(_player);
        GameResult expectedWinner = GameResult(uint8(GameResult.TEAM_0_WINS) + playerTeam);

        return game.result == expectedWinner;
    }
}
