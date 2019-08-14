const chai = require('chai');
const utils = require('ethers/utils');
const { createMockProvider, deployContract, getWallets, solidity } = require('ethereum-waffle');
const CoinFlip = require('../build/CoinFlip');

chai.use(solidity);
const { expect } = chai;

const generateSignature = async (wallet, secret) => {
  let message = utils.concat([utils.hexZeroPad(utils.hexlify(secret), 32)]);
  let messageHash = utils.arrayify(utils.keccak256(message));
  let sig = await wallet.signMessage(messageHash);

  return { sig: utils.splitSignature(sig), hash: utils.hashMessage(messageHash) };
};

describe('CoinFlip Test Suite', () => {
  let provider = createMockProvider();
  let [firstWallet, secondWallet] = getWallets(provider);
  let contractInstance;
  let secretNumber = 1357924680;
  let dummyHash = '0x2446f1fd773fbb9f080e674b60c6a033c7ed7427b8b9413cf28a2a4a6da9b56c';

  beforeEach(async () => {
    contractInstance = await deployContract(firstWallet, CoinFlip, []);
    expect(contractInstance.address).to.ok;
  });

  it('Should be able to create new game', async () => {
    let { hash, sig } = await generateSignature(firstWallet, secretNumber);
    let val = 100;
    await expect(contractInstance.newGame(1, 10, hash, sig.v, sig.r, sig.s, { value: val }))
      .to.emit(contractInstance, 'WagerMade')
      .withArgs(firstWallet.address, val, hash);

    expect((await contractInstance.games(1))[0]).to.eq(firstWallet.address);
  });

  it('Should fail creating new game with bad signature', async () => {
    await expect(
      contractInstance.newGame(1, 10, dummyHash, 27, dummyHash, dummyHash)
    ).to.be.revertedWith('bad signature');
  });

  it('Should fail to create new game without sending ether', async () => {
    let { hash, sig } = await generateSignature(firstWallet, secretNumber);
    await expect(contractInstance.newGame(1, 10, hash, sig.v, sig.r, sig.s)).to.be.reverted;
  });

  it('Should fail to cancel a game by someone else who not the first player', async () => {
    let { hash, sig } = await generateSignature(firstWallet, secretNumber);
    let val = 1000;
    await expect(contractInstance.newGame(1, 10, hash, sig.v, sig.r, sig.s, { value: val }))
      .to.emit(contractInstance, 'WagerMade')
      .withArgs(firstWallet.address, val, hash);

    const anotherWallet = contractInstance.connect(secondWallet);
    await expect(anotherWallet.cancelBetting(1)).to.be.reverted;
  });

  it('Should be able to accept the existing game as second player', async () => {
    let { hash: hash1, sig: sig1 } = await generateSignature(firstWallet, secretNumber);
    let { hash: hash2, sig: sig2 } = await generateSignature(secondWallet, secretNumber);
    let val = 100;
    await expect(contractInstance.newGame(1, 10, hash1, sig1.v, sig1.r, sig1.s, { value: val }))
      .to.emit(contractInstance, 'WagerMade')
      .withArgs(firstWallet.address, val, hash1);

    const anotherWallet = contractInstance.connect(secondWallet);
    await expect(anotherWallet.acceptBetting(1, hash2, sig2.v, sig2.r, sig2.s, { value: val }))
      .to.emit(contractInstance, 'WagerAccepted')
      .withArgs(secondWallet.address, hash2);

    expect((await contractInstance.games(1))[0]).to.eq(firstWallet.address);
    expect((await contractInstance.games(1))[1]).to.eq(secondWallet.address);
  });
});
