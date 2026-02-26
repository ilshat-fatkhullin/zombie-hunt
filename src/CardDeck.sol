// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/*
Ensures only valid cards are played:
- Manage card inventory (7 initial cards per player)
- Handle card types (regular numbered cards, Zombie, Shotgun, Vaccine)
- Track card distribution and transfers
- Verify card validity for each player
*/
enum CardType {
    NUMBER, // Regular numbered cards (1-10)
    ZOMBIE, // Trumps all cards, infects loser
    SHOTGUN, // Eliminates zombies
    VACCINE // Cancels out zombie card
}

enum CardSuit {
    HEARTS,
    DIAMONDS,
    CLUBS,
    SPADES
}

struct Card {
    CardType cardType;
    CardSuit suit;
    uint8 number; // 1-10 for NUMBER cards, 0 for special cards
}

contract CardDeck {
    // Player's card inventory: player address => array of card indices
    mapping(address => uint256[]) public playerCards;

    // Card details: card index => Card
    mapping(uint256 => Card) public cardDetails;

    // Tracks all cards by index
    uint256 private cardCounter = 0;

    // Special card tracking
    mapping(address => bool) public hasZombieCard;
    mapping(address => bool) public hasShotgunCard;
    mapping(address => uint256[]) public vaccineCards;

    // Events
    event CardDealt(address indexed player, uint256 cardIndex);
    event CardTransferred(address indexed from, address indexed to, uint256 cardIndex);
    event CardRemoved(address indexed player, uint256 cardIndex);
    event ZombieCardGiven(address indexed player);
    event ShotgunCardGiven(address indexed player);
    event VaccineCardGiven(address indexed player);

    // Create a card
    function _createCard(CardType _type, CardSuit _suit, uint8 _number) private returns (uint256) {
        cardDetails[cardCounter] = Card({cardType: _type, suit: _suit, number: _number});
        uint256 cardIndex = cardCounter;
        cardCounter++;
        return cardIndex;
    }

    // Deal initial deck: 7 cards per player (numbers 1-10 of each suit)
    // + 1 Zombie card per team (16 players) -> 1 zombie per team
    // + 1 Shotgun card per player
    // + Vaccine cards distributed per team
    function dealInitialCards(address[] calldata _players, uint256[] calldata _teams) external {
        require(_players.length == _teams.length, "Players and teams length mismatch");
        require(_players.length == 64, "Exactly 64 players required (4 teams of 16)");

        // Deal 7 numbered cards to each player
        for (uint256 i = 0; i < _players.length; i++) {
            uint256 team = _teams[i];
            require(team < 4, "Invalid team");

            // Deal 2 cards from each suit (8 cards total, pick 7)
            // For simplicity: deal cards 1-7 of different suits across all players
            for (uint8 suit = 0; suit < 4; suit++) {
                uint8 number = uint8((i + suit) % 10) + 1; // Distribute numbers 1-10
                uint256 cardIndex = _createCard(CardType.NUMBER, CardSuit(suit), number);
                playerCards[_players[i]].push(cardIndex);
                emit CardDealt(_players[i], cardIndex);
            }
        }

        // Assign exactly 1 Zombie card per team
        for (uint256 team = 0; team < 4; team++) {
            address zombiePlayer = _players[team * 16]; // First player of each team
            uint256 zombieIndex = _createCard(CardType.ZOMBIE, CardSuit.HEARTS, 0);
            playerCards[zombiePlayer].push(zombieIndex);
            hasZombieCard[zombiePlayer] = true;
            emit ZombieCardGiven(zombiePlayer);
        }

        // Assign 1 Shotgun card per player (all players)
        for (uint256 i = 0; i < _players.length; i++) {
            uint256 shotgunIndex = _createCard(CardType.SHOTGUN, CardSuit.DIAMONDS, 0);
            playerCards[_players[i]].push(shotgunIndex);
            hasShotgunCard[_players[i]] = true;
            emit ShotgunCardGiven(_players[i]);
        }

        // Assign Vaccine cards: 4 per team, cannot use on self
        for (uint256 team = 0; team < 4; team++) {
            for (uint8 v = 0; v < 4; v++) {
                address vaccinePlayer = _players[team * 16 + v]; // Distribute among team members
                uint256 vaccineIndex = _createCard(CardType.VACCINE, CardSuit.CLUBS, 0);
                playerCards[vaccinePlayer].push(vaccineIndex);
                vaccineCards[vaccinePlayer].push(vaccineIndex);
                emit VaccineCardGiven(vaccinePlayer);
            }
        }
    }

    // Get player's cards
    function getPlayerCards(address _player) external view returns (uint256[] memory) {
        return playerCards[_player];
    }

    // Get card details
    function getCardDetails(uint256 _cardIndex) external view returns (CardType, CardSuit, uint8) {
        Card memory card = cardDetails[_cardIndex];
        return (card.cardType, card.suit, card.number);
    }

    // Get player card count
    function getCardCount(address _player) external view returns (uint256) {
        return playerCards[_player].length;
    }

    // Check if player has a specific card
    function hasCard(address _player, uint256 _cardIndex) external view returns (bool) {
        uint256[] memory cards = playerCards[_player];
        for (uint256 i = 0; i < cards.length; i++) {
            if (cards[i] == _cardIndex) {
                return true;
            }
        }
        return false;
    }

    // Check if player has a card of specific suit
    function hasCardOfSuit(address _player, CardSuit _suit) external view returns (bool) {
        uint256[] memory cards = playerCards[_player];
        for (uint256 i = 0; i < cards.length; i++) {
            if (cardDetails[cards[i]].suit == _suit && cardDetails[cards[i]].cardType == CardType.NUMBER) {
                return true;
            }
        }
        return false;
    }

    // Validate card placement (must be NUMBER type and valid suit match)
    function validateCardPlacement(address _player, uint256 _cardIndex, CardSuit _requiredSuit)
        external
        view
        returns (bool)
    {
        uint256[] memory cards = playerCards[_player];
        bool cardExists = false;

        for (uint256 i = 0; i < cards.length; i++) {
            if (cards[i] == _cardIndex) {
                cardExists = true;
                break;
            }
        }

        if (!cardExists) return false;

        Card memory card = cardDetails[_cardIndex];

        // Card must be a NUMBER card and match required suit
        if (card.cardType != CardType.NUMBER) return false;
        if (card.suit != _requiredSuit) return false;

        return true;
    }

    // Transfer card from one player to another (winner gets card from loser)
    function transferCard(address _from, address _to, uint256 _cardIndex) external {
        require(_from != address(0) && _to != address(0), "Invalid addresses");

        // Remove card from sender
        _removeCardFromPlayer(_from, _cardIndex);

        // Add card to recipient
        playerCards[_to].push(_cardIndex);
        emit CardTransferred(_from, _to, _cardIndex);
    }

    // Remove card from player (used when card is consumed, e.g., Shotgun)
    function removeCard(address _player, uint256 _cardIndex) external {
        _removeCardFromPlayer(_player, _cardIndex);
        emit CardRemoved(_player, _cardIndex);
    }

    // Internal function to remove card from player
    function _removeCardFromPlayer(address _player, uint256 _cardIndex) private {
        uint256[] storage cards = playerCards[_player];
        for (uint256 i = 0; i < cards.length; i++) {
            if (cards[i] == _cardIndex) {
                cards[i] = cards[cards.length - 1];
                cards.pop();
                return;
            }
        }
        revert("Card not found in player's hand");
    }

    // Get highest numbered card of a suit in player's hand
    function getHighestCardOfSuit(address _player, CardSuit _suit) external view returns (uint256, uint8) {
        uint256[] memory cards = playerCards[_player];
        uint8 maxNumber = 0;
        uint256 maxCardIndex = 0;

        for (uint256 i = 0; i < cards.length; i++) {
            Card memory card = cardDetails[cards[i]];
            if (card.suit == _suit && card.cardType == CardType.NUMBER && card.number > maxNumber) {
                maxNumber = card.number;
                maxCardIndex = cards[i];
            }
        }

        return (maxCardIndex, maxNumber);
    }

    // Check special card status
    function hasZombie(address _player) external view returns (bool) {
        return hasZombieCard[_player];
    }

    function hasShotgun(address _player) external view returns (bool) {
        return hasShotgunCard[_player];
    }

    function getVaccineCards(address _player) external view returns (uint256[] memory) {
        return vaccineCards[_player];
    }
}
