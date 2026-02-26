// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PlayerRegistry.sol";
import "./CardDeck.sol";
import "./SpecialCards.sol";

/*
Handles individual game logic and calls dependent contracts for validation:
- Orchestrate one-on-one games at tables
- Verify card placement rules (same suit matching)
- Calculate cumulative totals and winners
- Process card transfers between players
*/

enum MatchState {
    PENDING, // Waiting for both players
    SUIT_CHOSEN, // Initial suit has been chosen
    CARDS_PLAYED, // Both players have played cards
    COMPLETED, // Match finished
    CANCELLED // Match cancelled
}

struct MatchRound {
    address player1;
    address player2;
    CardSuit requiredSuit;
    uint256 player1CardIndex;
    uint256 player2CardIndex;
    uint8 player1CardNumber;
    uint8 player2CardNumber;
    uint256 player1Total;
    uint256 player2Total;
    address winner;
    MatchState state;
    uint256 timestamp;
}

contract GameMatch {
    PlayerRegistry public playerRegistry;
    CardDeck public cardDeck;
    SpecialCards public specialCards;

    // Matches: match ID => match details
    mapping(uint256 => MatchRound) public matches;
    uint256 public matchCounter = 0;

    // Track player's current match
    mapping(address => uint256) public playerCurrentMatch;

    // Events
    event MatchCreated(uint256 indexed matchId, address indexed player1, address indexed player2);
    event SuitChosen(uint256 indexed matchId, CardSuit suit);
    event CardPlayed(uint256 indexed matchId, address indexed player, uint256 cardIndex, uint8 cardNumber);
    event MatchCompleted(uint256 indexed matchId, address indexed winner, address indexed loser);
    event CardTransferredToWinner(
        uint256 indexed matchId, address indexed winner, address indexed loser, uint256 cardIndex
    );
    event MatchCancelled(uint256 indexed matchId);

    constructor(address _playerRegistry, address _cardDeck, address _specialCards) {
        playerRegistry = PlayerRegistry(_playerRegistry);
        cardDeck = CardDeck(_cardDeck);
        specialCards = SpecialCards(_specialCards);
    }

    // Create a new match between two players
    function createMatch(address _player1, address _player2) external returns (uint256) {
        require(playerRegistry.isPlayerRegistered(_player1), "Player 1 not registered");
        require(playerRegistry.isPlayerRegistered(_player2), "Player 2 not registered");
        require(_player1 != _player2, "Cannot play against yourself");

        // Check players are not already in a match
        require(
            matches[playerCurrentMatch[_player1]].state == MatchState.COMPLETED || playerCurrentMatch[_player1] == 0,
            "Player 1 already in match"
        );
        require(
            matches[playerCurrentMatch[_player2]].state == MatchState.COMPLETED || playerCurrentMatch[_player2] == 0,
            "Player 2 already in match"
        );

        // Check players are not eliminated
        require(playerRegistry.getPlayerStatus(_player1) != PlayerStatus.ELIMINATED, "Player 1 is eliminated");
        require(playerRegistry.getPlayerStatus(_player2) != PlayerStatus.ELIMINATED, "Player 2 is eliminated");

        // Check both players have cards
        require(cardDeck.getCardCount(_player1) > 0, "Player 1 has no cards");
        require(cardDeck.getCardCount(_player2) > 0, "Player 2 has no cards");

        uint256 matchId = matchCounter++;

        matches[matchId] = MatchRound({
            player1: _player1,
            player2: _player2,
            requiredSuit: CardSuit.HEARTS, // Default, will be set when card is played
            player1CardIndex: 0,
            player2CardIndex: 0,
            player1CardNumber: 0,
            player2CardNumber: 0,
            player1Total: 0,
            player2Total: 0,
            winner: address(0),
            state: MatchState.PENDING,
            timestamp: block.timestamp
        });

        playerCurrentMatch[_player1] = matchId;
        playerCurrentMatch[_player2] = matchId;

        emit MatchCreated(matchId, _player1, _player2);
        return matchId;
    }

    // Play a card in the match (can be called by either player)
    function playCard(uint256 _matchId, address _player, uint256 _cardIndex) external {
        MatchRound storage matchRound = matches[_matchId];

        require(matchRound.state != MatchState.COMPLETED, "Match already completed");
        require(matchRound.state != MatchState.CANCELLED, "Match is cancelled");
        require(matchRound.player1 == _player || matchRound.player2 == _player, "Player not in this match");
        require(cardDeck.hasCard(_player, _cardIndex), "Player does not have this card");

        // If this is the first card played, it determines the suit
        if (matchRound.state == MatchState.PENDING) {
            matchRound.state = MatchState.SUIT_CHOSEN;
            (, CardSuit cardSuit,) = cardDeck.cardDetails(_cardIndex);
            matchRound.requiredSuit = cardSuit;
        }

        // Validate card placement (must match suit)
        require(
            cardDeck.validateCardPlacement(_player, _cardIndex, matchRound.requiredSuit),
            "Card does not match required suit"
        );

        // Get card details
        (CardType cardType,, uint8 number) = cardDeck.getCardDetails(_cardIndex);
        require(cardType == CardType.NUMBER, "Cannot play special cards in regular match");

        // Record which player played the card
        if (_player == matchRound.player1) {
            require(matchRound.player1CardIndex == 0, "Player 1 already played");
            matchRound.player1CardIndex = _cardIndex;
            matchRound.player1CardNumber = number;
        } else {
            require(matchRound.player2CardIndex == 0, "Player 2 already played");
            matchRound.player2CardIndex = _cardIndex;
            matchRound.player2CardNumber = number;
        }

        emit CardPlayed(_matchId, _player, _cardIndex, number);

        // If both players have played, determine winner
        if (matchRound.player1CardIndex != 0 && matchRound.player2CardIndex != 0) {
            _completeMatch(_matchId);
        }
    }

    // Internal function to complete the match and determine winner
    function _completeMatch(uint256 _matchId) private {
        MatchRound storage matchRound = matches[_matchId];

        require(matchRound.state == MatchState.SUIT_CHOSEN, "Both players must have played cards");

        // The player with the highest card number wins
        if (matchRound.player1CardNumber > matchRound.player2CardNumber) {
            matchRound.winner = matchRound.player1;
            _processMatchWin(_matchId, matchRound.player1, matchRound.player2);
        } else if (matchRound.player2CardNumber > matchRound.player1CardNumber) {
            matchRound.winner = matchRound.player2;
            _processMatchWin(_matchId, matchRound.player2, matchRound.player1);
        } else {
            // Tie - no one wins, both cards are discarded
            // In this case, we need to handle differently
            matchRound.winner = address(0);
            // Remove both cards from play
            cardDeck.removeCard(matchRound.player1, matchRound.player1CardIndex);
            cardDeck.removeCard(matchRound.player2, matchRound.player2CardIndex);
        }

        matchRound.state = MatchState.COMPLETED;
    }

    // Process the win: transfer card from loser to winner
    function _processMatchWin(uint256 _matchId, address _winner, address _loser) private {
        MatchRound storage matchRound = matches[_matchId];

        uint256 loserCardIndex;
        if (_winner == matchRound.player1) {
            loserCardIndex = matchRound.player2CardIndex;
        } else {
            loserCardIndex = matchRound.player1CardIndex;
        }

        // Transfer losing card to winner
        cardDeck.transferCard(_loser, _winner, loserCardIndex);

        // Remove winning card from play (it stays with the winner, not transferred)
        uint256 winnerCardIndex;
        if (_winner == matchRound.player1) {
            winnerCardIndex = matchRound.player1CardIndex;
        } else {
            winnerCardIndex = matchRound.player2CardIndex;
        }
        cardDeck.removeCard(_winner, winnerCardIndex);

        emit CardTransferredToWinner(_matchId, _winner, _loser, loserCardIndex);
        emit MatchCompleted(_matchId, _winner, _loser);
    }

    // Cancel a match (if someone has no cards, etc.)
    function cancelMatch(uint256 _matchId) external {
        MatchRound storage matchRound = matches[_matchId];
        require(matchRound.state != MatchState.COMPLETED, "Match already completed");
        require(matchRound.state != MatchState.CANCELLED, "Match already cancelled");

        matchRound.state = MatchState.CANCELLED;
        playerCurrentMatch[matchRound.player1] = 0;
        playerCurrentMatch[matchRound.player2] = 0;

        emit MatchCancelled(_matchId);
    }

    // Get match details
    function getMatchDetails(uint256 _matchId)
        external
        view
        returns (
            address player1,
            address player2,
            uint8 player1CardNumber,
            uint8 player2CardNumber,
            address winner,
            MatchState state
        )
    {
        MatchRound storage matchRound = matches[_matchId];
        return (
            matchRound.player1,
            matchRound.player2,
            matchRound.player1CardNumber,
            matchRound.player2CardNumber,
            matchRound.winner,
            matchRound.state
        );
    }

    // Get match state
    function getMatchState(uint256 _matchId) external view returns (MatchState) {
        return matches[_matchId].state;
    }

    // Check if match is complete
    function isMatchComplete(uint256 _matchId) external view returns (bool) {
        return matches[_matchId].state == MatchState.COMPLETED;
    }

    // Get player's current match ID
    function getPlayerCurrentMatch(address _player) external view returns (uint256) {
        return playerCurrentMatch[_player];
    }

    // Calculate cumulative total for a player (sum of all numbered cards)
    function calculatePlayerTotal(address _player) external view returns (uint256) {
        uint256[] memory cards = cardDeck.getPlayerCards(_player);
        uint256 total = 0;

        for (uint256 i = 0; i < cards.length; i++) {
            (CardType cardType,, uint8 number) = cardDeck.getCardDetails(cards[i]);
            if (cardType == CardType.NUMBER) {
                total += number;
            }
        }

        return total;
    }
}
