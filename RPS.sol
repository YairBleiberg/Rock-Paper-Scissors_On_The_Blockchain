// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract RPS{
    // This contract lets players play rock-paper-scissors.
    // its constructor receives a uint k which is the number of blocks mined before a reveal phase is over.

    // players can send the contract money to fund their bets, see their balance and withdraw it, as long as the amount is not in an active game.

    // the game mechanics: The players choose a game_id (some uint) that is not being currently used. They then each call make_move() making a bet and committing to a move.
    // in the next phase each of them reveals their committment, and once the second commit is done, the game is over. The winner gets the amount of money they agreed on.

    enum GameState {NO_GAME, //signifies that there is no game with this id (or there was and it is over)
                    MOVE1, //signifies that a single move was entered
                    MOVE2, //a second move was enetered
                    REVEAL1, //one of the moves was revealed, and the reveal phase just started
                    LATE // one of the moves was revealed, and enough blocks have been mined since so that the other player is considered late.
    } // These correspond to values 0,1,2,3,4
    enum Move{NONE, ROCK, PAPER, SCISSORS} //These correspond to values 0,1,2,3

    struct Game {
        uint game_id;
        GameState gamestate;
        uint bet_amount;
        address player1;
        address player2;
        address first_reveal_player;
        bytes32 first_commitment;
        bytes32 second_commitment;
        Move first_move;
        Move second_move;
        uint reveal1_stage_block_number;
    }
    uint reveal_period_length;
    mapping(uint => Game) public games_database;
    mapping(address => uint) public balances;


    constructor(uint _reveal_period_length){
        // Constructs a new contract that allows users to play multiple rock-paper-scissors games.
        // If one of the players does not reveal the move committed to, then the _reveal_period_length
        // is the number of blocks that a player needs to wait from the moment of revealing her move until
        // she can calim that the other player loses (for not revealing).
        // The reveal_period_length must be at least 1 block.
        if (_reveal_period_length < 1){
            revert();
        }
        reveal_period_length = _reveal_period_length;

    }

    function check_commitment(bytes32 commitment, Move move, bytes32 key) pure public returns(bool){
        // A utility function that can be used to check commitments. See also commit.py.
        // python code to generate the commitment is:
        //  commitment = HexBytes(Web3.solidityKeccak(['int256', 'bytes32'], [move, key]))
        return keccak256(abi.encodePacked(uint(move),key)) == commitment;
    }

    function get_game_state(uint game_id) external returns(GameState){
        // Returns the state of the game at the current address as a GameState (see enum definition)
        if (games_database[game_id].gamestate == GameState.NO_GAME){
            return GameState.NO_GAME;
        }
        else if (block.number >= games_database[game_id].reveal1_stage_block_number + reveal_period_length &&
            games_database[game_id].gamestate == GameState.REVEAL1) {
            games_database[game_id].gamestate = GameState.LATE;
        }
        return games_database[game_id].gamestate;
    }


    function make_move(uint game_id, uint bet_amount, bytes32 hidden_move) external{
        // The first call to this function starts the game. The second call finishes the commit phase.
        // The amount is the amount of money (in wei) that a user is willing to bet.
        // The amount provided in the call by the second player is ignored, but the user must have an amount matching that of the game to bet.
        // amounts that are wagered are locked for the duration of the game.
        // A player should not be allowed to enter a commitment twice.
        // If two moves have already been entered, then this call reverts.
        if (games_database[game_id].gamestate == GameState.NO_GAME){
            require(bet_amount >= 1);
            require(balances[msg.sender] >= bet_amount);
            Game memory current_game;
            current_game.game_id = game_id;
            current_game.bet_amount = bet_amount;
            current_game.gamestate = GameState.MOVE1;
            current_game.first_commitment = hidden_move;
            current_game.player1 = address(msg.sender);
            games_database[game_id] = current_game;
            balances[msg.sender] -= bet_amount;
            return;
        }
        else if (games_database[game_id].gamestate == GameState.MOVE1){
            require(msg.sender != games_database[game_id].player1);
            require(games_database[game_id].bet_amount <= balances[msg.sender]);
            Game memory current_game = games_database[game_id];
            current_game.gamestate = GameState.MOVE2;
            current_game.second_commitment = hidden_move;
            current_game.player2 = address(msg.sender);
            games_database[game_id] = current_game;
            balances[address(msg.sender)] -= current_game.bet_amount;
            return;
        }
        revert();
    }


    function cancel_game(uint game_id) external{
        // This function allows a player to cancel the game, but only if the other player did not yet commit to his move.
        // a canceled game returns the funds to the player. Only the player that made the first move can call this function, and it will run only if
        // no other commitment for a move was entered.
        if (games_database[game_id].gamestate == GameState.NO_GAME) { return; }
        Game memory current_game =  games_database[game_id];
        require( current_game.gamestate == GameState.MOVE1 );
        require( address(msg.sender) == current_game.player1);
        balances[address(msg.sender)] += current_game.bet_amount;
        delete games_database[game_id];
    }

    function reveal_move(uint game_id, Move move, bytes32 key) external{
        // Reveals the move of a player (which is checked against his commitment using the key)
        // The first call to this function can be made only after two moves have been entered (otherwise the function reverts).
        // This call will begin the reveal period.
        // the second call (if called by the player that entered the second move) reveals her move, ends the game, and awards the money to the winner.
        // if a player has already revealed, and calls this function again, then this call reverts.
        // only players that have committed a move may reveal.
        if (games_database[game_id].gamestate == GameState.NO_GAME){
            revert();
        }
        Game memory current_game = games_database[game_id];
        require(msg.sender == current_game.player1 || msg.sender == current_game.player2);
        bytes32 commitment = current_game.first_commitment;
        if ( msg.sender == current_game.player2 ){ commitment = current_game.second_commitment; }
        require(check_commitment(commitment, move, key));
        if (current_game.gamestate == GameState.MOVE2){
            current_game.gamestate = GameState.REVEAL1;
            current_game.reveal1_stage_block_number = block.number;
            if (msg.sender == current_game.player1){
                current_game.first_move = move;
                current_game.first_reveal_player = current_game.player1;
                }
            else {
                current_game.second_move = move;
                current_game.first_reveal_player = current_game.player2;
                }
            games_database[game_id] = current_game;
            return;
        }
        else if (current_game.gamestate == GameState.REVEAL1){
            if (current_game.first_reveal_player == current_game.player1){
                require(msg.sender == current_game.player2);
                current_game.second_move = move;
            }
            else {
                require(msg.sender == current_game.player1);
                current_game.first_move = move;
            }
            uint winner = RPSwinner(current_game.first_move, current_game.second_move);
            if (winner == 0){
                balances[current_game.player1] += current_game.bet_amount;
                balances[current_game.player2] += current_game.bet_amount;
                }
            else if (winner == 1){ balances[current_game.player1] += 2*current_game.bet_amount; }
            else if (winner == 2){ balances[current_game.player2] += 2*current_game.bet_amount; }
            delete games_database[current_game.game_id];
        }
        else{ revert(); }
    }


    function RPSwinner(Move move1, Move move2) internal returns(uint) {
        if (move1 == move2){ return 0; }
        else if (move1 == Move.NONE){ return 2; }
        else if (move2 == Move.NONE){ return 1; }
        else if (move1 == Move.ROCK && move2 == Move.PAPER){ return 2; }
        else if (move1 == Move.ROCK && move2 == Move.SCISSORS){ return 1; }
        else if (move1 == Move.PAPER && move2 == Move.SCISSORS){ return 2; }
        else if (move1 == Move.PAPER && move2 == Move.ROCK){ return 1; }
        else if (move1 == Move.SCISSORS && move2 == Move.ROCK) { return 2; }
        else if (move1 == Move.SCISSORS && move2 == Move.PAPER) { return 1; }
        else { return 0; }
    }

    function reveal_phase_ended(uint game_id) external{
        // If no second reveal is made, and the reveal period ends, the player that did reveal can claim all funds wagered in this game.
        // The game then ends, and the game id is released (and can be reused in another game).
        // this function can only be called by the first revealer. If the reveal phase is not over, this function reverts.
        if (games_database[game_id].gamestate == GameState.NO_GAME){
        revert();
        }
        Game memory current_game = games_database[game_id];
        require(current_game.gamestate == GameState.REVEAL1);
        require(msg.sender == current_game.first_reveal_player);
        require(block.number >= current_game.reveal1_stage_block_number + reveal_period_length);
        balances[current_game.first_reveal_player] += 2*current_game.bet_amount;
        delete games_database[current_game.game_id];
    }

    ////////// Handling money ////////////////////

    function balanceOf(address player) external returns(uint){
        // returns the balance of the given player. Funds that are wagered in games that did not complete yet are not counted as part of the balance.
        return balances[player];
    }

    function withdraw(uint amount) external{
        // Withdraws amount from the account of the sender
        // (available funds are those that were deposited or won but not currently staked in a game).
        {
            require(balances[msg.sender] >= amount);
            (bool success,) = msg.sender.call{value: amount}("");
            require(success);
            balances[msg.sender] -= amount;
        }

    }

    receive() external payable{
        // adds eth to the account of the message sender.
        balances[msg.sender] += msg.value;
    }
}