// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PlayerRegistry.sol";
import "./CardDeck.sol";

/*
Intercepts match outcomes to apply Zombie/Shotgun/Vaccine effects:
- Handle Zombie card logic (infection, doubling)
- Manage Shotgun card elimination
- Manage Vaccine card counter-infection
- Prevent invalid special card uses
*/
contract SpecialCards {
    PlayerRegistry public playerRegistry;
    CardDeck public cardDeck;

    // Track if zombie card has been used this round
    mapping(address => bool) public zombieCardUsedThisRound;

    // Track if vaccine has been used on a specific zombie
    mapping(address => mapping(address => bool)) public vaccineUsed; // vaccine user => zombie => used

    // Events
    event ZombieCardPlayed(address indexed zombie, address indexed victim);
    event VictimInfected(address indexed victim, address indexed zombie);
    event ZombieCardAcquired(address indexed newZombie, address indexed oldZombie);
    event ShotgunCardUsed(address indexed shooter, address indexed zombie);
    event ZombieEliminated(address indexed zombie);
    event VaccineCardUsed(address indexed vaccineUser, address indexed zombie);
    event ZombieReverted(address indexed zombie);

    constructor(address _playerRegistry, address _cardDeck) {
        playerRegistry = PlayerRegistry(_playerRegistry);
        cardDeck = CardDeck(_cardDeck);
    }

    // Use Zombie card in a match
    // Zombie card trumps all other cards - loser becomes infected
    function useZombieCard(address _zombie, address _victim, uint256 _zombieCardIndex) external {
        require(playerRegistry.isPlayerRegistered(_zombie), "Zombie player not registered");
        require(playerRegistry.isPlayerRegistered(_victim), "Victim player not registered");
        require(!zombieCardUsedThisRound[_zombie], "Zombie card already used this round");

        // Verify zombie has the zombie card
        require(cardDeck.hasZombie(_zombie), "Player does not have zombie card");

        // Victim cannot be from a different team... actually, wait, let me re-read the rules
        // Actually, the zombie card just infects the loser of the game, doesn't matter team

        emit ZombieCardPlayed(_zombie, _victim);

        // Infect the victim
        _infectPlayer(_victim, _zombie, _zombieCardIndex);

        zombieCardUsedThisRound[_zombie] = true;
    }

    // Internal function to infect a player
    function _infectPlayer(address _victim, address _zombie, uint256 _zombieCardIndex) private {
        // Change victim status to ZOMBIE
        playerRegistry.updatePlayerStatus(_victim, PlayerStatus.ZOMBIE);

        // Transfer zombie card from current zombie to victim
        cardDeck.transferCard(_zombie, _victim, _zombieCardIndex);

        emit VictimInfected(_victim, _zombie);
        emit ZombieCardAcquired(_victim, _zombie);
    }

    // Use Shotgun card to eliminate a zombie
    // Can be used at any point, effective only against zombies, disappears after use
    function useShotgunCard(address _shooter, address _zombie, uint256 _shotgunCardIndex) external {
        require(playerRegistry.isPlayerRegistered(_shooter), "Shooter not registered");
        require(playerRegistry.isPlayerRegistered(_zombie), "Zombie not registered");

        // Verify shooter has the shotgun card
        require(cardDeck.hasShotgun(_shooter), "Player does not have shotgun card");

        // Only effective against zombies
        require(playerRegistry.getPlayerStatus(_zombie) == PlayerStatus.ZOMBIE, "Shotgun only works on zombies");

        // Cannot eliminate already eliminated players
        require(
            playerRegistry.getPlayerStatus(_shooter) != PlayerStatus.ELIMINATED, "Eliminated players cannot use shotgun"
        );

        emit ShotgunCardUsed(_shooter, _zombie);

        // Eliminate the zombie (GAME OVER for the zombie)
        playerRegistry.eliminatePlayer(_zombie);

        // Remove shotgun card (consumed after use)
        cardDeck.removeCard(_shooter, _shotgunCardIndex);

        emit ZombieEliminated(_zombie);
    }

    // Use Vaccine card to revert a player back to human
    // Can only be used on other players (not self)
    function useVaccineCard(address _vaccineUser, address _zombie, uint256 _vaccineCardIndex) external {
        require(playerRegistry.isPlayerRegistered(_vaccineUser), "Vaccine user not registered");
        require(playerRegistry.isPlayerRegistered(_zombie), "Zombie not registered");

        // Cannot use on self
        require(_vaccineUser != _zombie, "Cannot use vaccine on yourself");

        // Verify vaccine user has the vaccine card
        uint256[] memory vaccineCards = cardDeck.getVaccineCards(_vaccineUser);
        bool hasVaccine = false;
        for (uint256 i = 0; i < vaccineCards.length; i++) {
            if (vaccineCards[i] == _vaccineCardIndex) {
                hasVaccine = true;
                break;
            }
        }
        require(hasVaccine, "Player does not have this vaccine card");

        // Can only be used on zombies
        require(playerRegistry.getPlayerStatus(_zombie) == PlayerStatus.ZOMBIE, "Vaccine only works on zombies");

        // Cannot use vaccine on already eliminated players
        require(
            playerRegistry.getPlayerStatus(_zombie) != PlayerStatus.ELIMINATED, "Cannot vaccinate eliminated player"
        );

        // Prevent using same vaccine twice on same zombie
        require(!vaccineUsed[_vaccineUser][_zombie], "Vaccine already used on this zombie");

        emit VaccineCardUsed(_vaccineUser, _zombie);

        // Revert zombie back to human
        playerRegistry.updatePlayerStatus(_zombie, PlayerStatus.HUMAN);

        // Mark vaccine as used on this zombie
        vaccineUsed[_vaccineUser][_zombie] = true;

        // Vaccine card is consumed after use
        cardDeck.removeCard(_vaccineUser, _vaccineCardIndex);

        emit ZombieReverted(_zombie);
    }

    // Reset round state for zombie card usage
    function resetZombieCardRound(address _zombie) external {
        zombieCardUsedThisRound[_zombie] = false;
    }

    // Check if zombie has already used their card this round
    function hasZombieUsedCardThisRound(address _zombie) external view returns (bool) {
        return zombieCardUsedThisRound[_zombie];
    }

    // Check if vaccine has been used on a zombie
    function hasVaccineBeenUsed(address _vaccineUser, address _zombie) external view returns (bool) {
        return vaccineUsed[_vaccineUser][_zombie];
    }

    // Validate special card use - returns true if action is valid
    function validateZombieCardUse(address _zombie) external view returns (bool) {
        return
            playerRegistry.isPlayerRegistered(_zombie) && cardDeck.hasZombie(_zombie)
                && !zombieCardUsedThisRound[_zombie];
    }

    function validateShotgunCardUse(address _shooter, address _zombie) external view returns (bool) {
        return playerRegistry.isPlayerRegistered(_shooter) && playerRegistry.isPlayerRegistered(_zombie)
            && cardDeck.hasShotgun(_shooter) && playerRegistry.getPlayerStatus(_zombie) == PlayerStatus.ZOMBIE;
    }

    function validateVaccineCardUse(address _vaccineUser, address _zombie) external view returns (bool) {
        return _vaccineUser != _zombie && playerRegistry.isPlayerRegistered(_vaccineUser)
            && playerRegistry.isPlayerRegistered(_zombie)
            && playerRegistry.getPlayerStatus(_zombie) == PlayerStatus.ZOMBIE && !vaccineUsed[_vaccineUser][_zombie];
    }
}
