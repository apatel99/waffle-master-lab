pragma solidity >= 0.5.0 <= 0.6.0;

// Available Accounts
// ==================
// (0) 0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1 (~100 ETH)
// (1) 0xffcf8fdee72ac11b5c542428b35eef5769c409f0 (~100 ETH)
// (2) 0x22d491bde2303f2f43325b2108d26f1eaba1e32b (~100 ETH)
// (3) 0xe11ba2b4d45eaed5996cd0823791e0c93114882d (~100 ETH)
// (4) 0xd03ea8624c8c5987235048901fb614fdca89b117 (~100 ETH)
// (5) 0x95ced938f7991cd0dfcb48f0a06a40fa1af46ebc (~100 ETH)
// (6) 0x3e5e9111ae8eb78fe1cc3bb8915d5d461f3ef9a9 (~100 ETH)
// (7) 0x28a8746e75304c0780e011bed21c72cd78cd535e (~100 ETH)
// (8) 0xaca94ef8bd5ffee41947b4585a84bda5a3d3da6e (~100 ETH)
// (9) 0x1df62f291b2e969fb0849d99d9ce41e2f137006e (~100 ETH)

// Private Keys
// ==================
// (0) 0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d
// (1) 0x6cbed15c793ce57650b9877cf6fa156fbef513c4e6134f022a85b1ffdd59b2a1
// (2) 0x6370fd033278c143179d81c5526140625662b8daa446c22ee2d73db3707e620c
// (3) 0x646f1ce2fdad0e6deeeb5c7e8e5543bdde65e86029e2fd9fc169899c440a7913
// (4) 0xadd53f9a7e588d003326d1cbf9e4a43c061aadd9bc938c843a79e7b4fd2ad743
// (5) 0x395df67f0c2d2d9fe1ad08d1bc8b6627011959b79c53d7dd6a3536a33ab8a4fd
// (6) 0xe485d098507f54e7733a205420dfddbe58db035fa577fc294ebd14db90767a52
// (7) 0xa453611d9419d0e56f499079478fd72c37b251a94bfde4d19872c44cf65386e3
// (8) 0x829e924fdf021ba3dbbc4225edfece9aca04b929d6e75613329ca6f1d31c0bb4
// (9) 0xb0057716d5917badaf911b193b12b910811c1497b5bada8d7711f758981c3773

contract CoinFlip {
    enum State { OPENED, BETTING, ACCEPTED, CLOSED, CANCELLED }

    event WagerMade(address _player, uint256 _amount, bytes32 _secretHash);
    event WagerAccepted(address _player, bytes32 _secretHash);
    event WinnerFound(address _winner, uint256 _winningAmount, uint256 _timestamp);

    struct Game {
        address payable firstPlayer;
        address payable secondPlayer;
        uint256 betAmount;
        uint256 drawingAt;
        uint256 blockNumber;
        uint256 disputePeriodLength;
        mapping(address => bytes32) secretHashes;
        mapping(address => uint256) secretNumbers;
        address payable winner;
        State state;
    }

    mapping (uint256 => Game) public games;

    modifier uniqueId(uint256 uid) {
        require(games[uid].firstPlayer == address(0) && games[uid].secondPlayer == address(0), "CoinFlip: non unique id");
        _;
    }

    modifier atState(uint256 uid, State _state) {
        require(games[uid].state == _state, "CoinFlip: cannot be called at this stage");
        _;
    }

    modifier transitionState(uint256 uid, State _state) {
        _;
        games[uid].state = _state;
    }

    modifier validSignature(bytes32 h, uint8 v, bytes32 r, bytes32 s) {
        require(ecrecover(h, v, r, s) == msg.sender, "CoinFlip: bad signature");
        _;
    }

    modifier onlyPlayers(uint256 uid) {
        require(games[uid].firstPlayer == msg.sender || games[uid].secondPlayer == msg.sender, "CoinFlip: must be player");
        _;
    }

    function newGame(uint256 uid, uint256 _disputePeriodLength, bytes32 secretHash, uint8 v, bytes32 r, bytes32 s) public payable
            uniqueId(uid)
            validSignature(secretHash, v, r, s)
            transitionState(uid, State.BETTING) {
        require(msg.value > 0, "CoinFlip: invalid bet amount");
        games[uid].firstPlayer = msg.sender;
        games[uid].betAmount = msg.value;
        games[uid].secretHashes[msg.sender] = secretHash;
        games[uid].disputePeriodLength = _disputePeriodLength;

        emit WagerMade(msg.sender, msg.value, secretHash);
    }

    function cancelBetting(uint256 uid) public atState(uid, State.BETTING) transitionState(uid, State.CANCELLED) {
        require(games[uid].firstPlayer == msg.sender, "CoinFlip: must be initiator");
        require(games[uid].secondPlayer == address(0), "CoinFlip: cannot cancel");
        games[uid].firstPlayer.transfer(games[uid].betAmount);
    }

    function acceptBetting(uint256 uid, bytes32 secretHash, uint8 v, bytes32 r, bytes32 s) public payable
            atState(uid, State.BETTING)
            validSignature(secretHash, v, r, s)
            transitionState(uid, State.ACCEPTED) {
        require(msg.value == games[uid].betAmount, "CoinFlip: invalid bet amount");
        games[uid].secondPlayer = msg.sender;
        games[uid].secretHashes[msg.sender] = secretHash;
        games[uid].blockNumber = block.number;

        emit WagerAccepted(games[uid].secondPlayer, secretHash);
    }

    function revealSecretNumber(uint256 uid, uint256 secretNumber) public onlyPlayers(uid) atState(uid, State.ACCEPTED) {
        require(games[uid].blockNumber + games[uid].disputePeriodLength > block.number, "CoinFlip: too late");
        require(_hash(secretNumber) == games[uid].secretHashes[msg.sender], "CoinFlip: invalid secret hash");

        games[uid].secretNumbers[msg.sender] = secretNumber;
    }

    function calcWinner(uint256 uid) public onlyPlayers(uid) transitionState(uid, State.CLOSED) {
        require(games[uid].secretNumbers[games[uid].firstPlayer] != 0 && games[uid].secretNumbers[games[uid].secondPlayer] != 0, "CoinFlip: too early");
        bytes32 randomBytes = keccak256(abi.encodePacked(games[uid].secretNumbers[games[uid].firstPlayer], games[uid].secretNumbers[games[uid].secondPlayer]));
        uint256 coinSide = uint256(randomBytes) % 2;
        games[uid].winner = coinSide == 0 ? games[uid].firstPlayer: games[uid].secondPlayer;
        games[uid].drawingAt = now;
        uint256 winningAmount = games[uid].betAmount * 2;
        games[uid].winner.transfer(winningAmount);

        emit WinnerFound(games[uid].winner, winningAmount, games[uid].drawingAt);
    }

    function claimTimeOut(uint256 uid) public onlyPlayers(uid) atState(uid, State.ACCEPTED) transitionState(uid, State.CLOSED) {
        require(block.number > games[uid].blockNumber + games[uid].disputePeriodLength, "CoinFlip: too early");
        require(games[uid].secretNumbers[games[uid].firstPlayer] == 0 || games[uid].secretNumbers[games[uid].secondPlayer] == 0, "CoinFlip: cannot claim");

        if (games[uid].secretNumbers[games[uid].firstPlayer] != 0) {
            games[uid].firstPlayer.transfer(games[uid].betAmount * 2);
        }

        if (games[uid].secretNumbers[games[uid].secondPlayer] != 0) {
            games[uid].secondPlayer.transfer(games[uid].betAmount * 2);
        }
    }

    function _hash(uint256 _secretNumber) private view returns(bytes32) {
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, _secretNumber));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }
}
