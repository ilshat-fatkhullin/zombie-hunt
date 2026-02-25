# Zombie Hunt

DApp representation of the game from the Netflix series "Alice in Borderland"

## Rules
- The participants are divided into four teams of 16.
- Each player receives seven playing cards. The cards are used in one-on-one games at designated tables installed throughout the facility.
- Players have to place a card of the same suit as the hand dealt to them. The one with the highest cumulative total wins the game. The winning player receives one card from the losing player.
- The game contains three special cards: Zombie Card, Shotgun Card, and Vaccine Card.
    - The **Zombie card** (ゾンビカード, Zonbi kaado) is given to one person in each group; it trumps every other card in the deck. The losing player becomes infected by the zombie, and a Zombie card is added to their hand.
    - The **Shotgun card** (ショットカード, Shotto kaado) can stop zombies from multiplying by eliminating them. Each player is guaranteed to receive one Shotgun card, and the card can be used at any point in time regardless of the placement of a Zombie card on the table. The card is ineffective against humans and disappears after being used once.
    - The **Vaccine cards** (ワクチンカード, Wakuchin kaado) are distributed randomly between members of each group. When the card is placed, it cancels out the Zombie card and turns the zombie back into a human. The Vaccine card cannot be used on oneself.
- It is **GAME CLEAR** if the player is on the side with the most players at the end of the game (zombies vs. humans).
- It is **GAME OVER** if the player is a zombie and gets eliminated by a Shotgun card.
- It is **GAME OVER** if the player runs out of number cards.
- It is **GAME OVER** if the player is on the side with the fewest players at the end of the game (zombies vs. humans).

## Implementation
The implementation is based on [**TEN Protocol**](https://docs.ten.xyz/docs/overview/) to ensure data access control rules.