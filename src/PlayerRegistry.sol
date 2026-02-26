// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/*
Acts as the central state store for all player information:
- Track individual player profiles and status
- Store player scores and card counts
- Manage player state (alive, zombie, eliminated, human)
- Handle player elimination and status changes
*/
enum PlayerStatus {
    HUMAN,
    ZOMBIE,
    ELIMINATED
}

struct Player {
    address playerAddress;
    uint256 team;
    PlayerStatus status;
    uint256 cardCount;
    uint256 score;
    bool isRegistered;
}

contract PlayerRegistry {
    mapping(address => Player) public players;
    address[] public registeredPlayers;
    
    // Events
    event PlayerRegistered(address indexed player, uint256 team);
    event PlayerStatusChanged(address indexed player, PlayerStatus newStatus);
    event PlayerEliminated(address indexed player);
    event CardCountUpdated(address indexed player, uint256 newCardCount);
    event ScoreUpdated(address indexed player, uint256 newScore);

    // Modifiers
    modifier playerExists(address _player) {
        require(players[_player].isRegistered, "Player not registered");
        _;
    }

    modifier validTeam(uint256 _team) {
        require(_team < 4, "Invalid team number (0-3)");
        _;
    }

    // Register a new player
    function registerPlayer(address _player, uint256 _team) external validTeam(_team) {
        require(!players[_player].isRegistered, "Player already registered");
        require(_player != address(0), "Invalid player address");

        players[_player] = Player({
            playerAddress: _player,
            team: _team,
            status: PlayerStatus.HUMAN,
            cardCount: 7,
            score: 0,
            isRegistered: true
        });

        registeredPlayers.push(_player);
        emit PlayerRegistered(_player, _team);
    }

    // Update player status (HUMAN, ZOMBIE, ELIMINATED)
    function updatePlayerStatus(address _player, PlayerStatus _status) external playerExists(_player) {
        require(_status != PlayerStatus.ELIMINATED, "Use eliminatePlayer() for elimination");
        
        players[_player].status = _status;
        emit PlayerStatusChanged(_player, _status);
    }

    // Eliminate a player (GAME OVER condition)
    function eliminatePlayer(address _player) external playerExists(_player) {
        require(players[_player].status != PlayerStatus.ELIMINATED, "Player already eliminated");
        
        players[_player].status = PlayerStatus.ELIMINATED;
        emit PlayerEliminated(_player);
    }

    // Update card count
    function updateCardCount(address _player, uint256 _cardCount) external playerExists(_player) {
        require(_cardCount <= 52, "Card count exceeds deck size");
        
        players[_player].cardCount = _cardCount;
        emit CardCountUpdated(_player, _cardCount);
    }

    // Update player score
    function updateScore(address _player, uint256 _score) external playerExists(_player) {
        players[_player].score = _score;
        emit ScoreUpdated(_player, _score);
    }

    // Get player information
    function getPlayerStatus(address _player) external view playerExists(_player) returns (PlayerStatus) {
        return players[_player].status;
    }

    function getPlayerInfo(address _player) external view playerExists(_player) 
        returns (
            address playerAddress,
            uint256 team,
            PlayerStatus status,
            uint256 cardCount,
            uint256 score,
            bool isRegistered
        ) 
    {
        Player memory player = players[_player];
        return (player.playerAddress, player.team, player.status, player.cardCount, player.score, player.isRegistered);
    }

    function getPlayerCardCount(address _player) external view playerExists(_player) returns (uint256) {
        return players[_player].cardCount;
    }

    function getPlayerTeam(address _player) external view playerExists(_player) returns (uint256) {
        return players[_player].team;
    }

    // Check if player exists and is registered
    function isPlayerRegistered(address _player) external view returns (bool) {
        return players[_player].isRegistered;
    }

    // Check if player is eliminated
    function isPlayerEliminated(address _player) external view returns (bool) {
        return players[_player].isRegistered && players[_player].status == PlayerStatus.ELIMINATED;
    }

    // Get all registered players
    function getRegisteredPlayersCount() external view returns (uint256) {
        return registeredPlayers.length;
    }

    // Get all players for a specific team
    function getTeamPlayers(uint256 _team) external view validTeam(_team) returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < registeredPlayers.length; i++) {
            if (players[registeredPlayers[i]].team == _team) {
                count++;
            }
        }

        address[] memory teamPlayers = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < registeredPlayers.length; i++) {
            if (players[registeredPlayers[i]].team == _team) {
                teamPlayers[index] = registeredPlayers[i];
                index++;
            }
        }

        return teamPlayers;
    }

    // Count alive/zombie/eliminated players
    function countPlayersByStatus(PlayerStatus _status) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < registeredPlayers.length; i++) {
            if (players[registeredPlayers[i]].status == _status) {
                count++;
            }
        }
        return count;
    }

    // Count alive/zombie/eliminated players in a team
    function countTeamPlayersByStatus(uint256 _team, PlayerStatus _status) external view validTeam(_team) returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < registeredPlayers.length; i++) {
            address player = registeredPlayers[i];
            if (players[player].team == _team && players[player].status == _status) {
                count++;
            }
        }
        return count;
    }
}
