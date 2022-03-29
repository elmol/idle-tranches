// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCard.sol";

contract IdleCDOCardManager is ERC721Enumerable {
  using Counters for Counters.Counter;
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  uint256 public constant RATIO_PRECISION = 10**18;

  struct Card {
    uint256 exposure;
    uint256 amount;
    address cardAddress;
    address idleCDOAddress;
  }

  IdleCDO[] public idleCDOs;

  Counters.Counter private _tokenIds;
  Counters.Counter private _cardIds;

  mapping(uint256 => Card) private _cardMap;
  mapping(uint256 => uint256[]) private _cards;

  constructor(address[] memory _idleCDOAddress) ERC721("IdleCDOCardManager", "ICC") {
    for (uint256 i = 0; i < _idleCDOAddress.length; i++) {
      idleCDOs.push(IdleCDO(_idleCDOAddress[i]));
    }
  }

  function getIdleCDOs() public view returns (IdleCDO[] memory) {
    return idleCDOs;
  }

  function mint(
    address[] memory _addresses,
    uint256[] memory _amounts,
    uint256[] memory _exposures
  ) external returns (uint256) {
    //gas optimization, use one state read for each array length
    uint256 addressesLength = _addresses.length;
    uint256 amountsLength = _amounts.length;
    uint256 exposuresLength = _exposures.length;
    require(addressesLength == amountsLength && addressesLength == exposuresLength, "arrays length must match");

    bool amount = false;
    uint256 tokenId;
    IdleCDOCard _card;
    for (uint256 i = 0; i < addressesLength; i++) {
      if (_amounts[i] > 0) {
        if (!amount) {
          // mint the Idle CDO card
          _tokenIds.increment();
          tokenId = _tokenIds.current();
          _mint(msg.sender, tokenId);

          _card = new IdleCDOCard();
          amount = true;
        }
        _depositToCard(_card, _addresses[i], _exposures[i], _amounts[i]);

        uint256 _currId = _cardIds.current();
        _cardMap[_currId] = Card(_exposures[i], _amounts[i], address(_card), _addresses[i]);
        _cards[tokenId].push(_currId);
        _cardIds.increment();
      }
    }
    if (!amount) {
      require(amount, "cannot mint with no amount");
    }

    return tokenId;
  }

  function burn(uint256 _tokenId) external {
    require(msg.sender == ownerOf(_tokenId), "burn of card that is not own");

    _burn(_tokenId);

    address cardAddress = card(_tokenId, 0).cardAddress;

    // withdraw all positions
    uint256 cardLength = _cards[_tokenId].length;
    for (uint256 i = 0; i < cardLength; i++) {
      _withdrawFromCard(_tokenId, i);
      delete _cardMap[_cards[_tokenId][i]];
      delete _cards[_tokenId][i];
    }
    delete _cards[_tokenId];
    IdleCDOCard(cardAddress).destroy();
  }

  function card(uint256 _tokenId, uint256 _index) public view returns (Card memory) {
    return _cardMap[_cards[_tokenId][_index]];
  }

  function getApr(address _idleCDOAddress, uint256 _exposure) external view returns (uint256) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);

    // ratioAA = ratio of 1 - _exposure of the AA apr
    uint256 aprAA = idleCDO.getApr(idleCDO.AATranche());
    uint256 ratioAA = percentage(RATIO_PRECISION.sub(_exposure), aprAA);

    // ratioBB = ratio of _exposure of the BB apr
    uint256 aprBB = idleCDO.getApr(idleCDO.BBTranche());
    uint256 ratioBB = percentage(_exposure, aprBB);

    return ratioAA.add(ratioBB);
  }

  function cardIndexes(uint256 _tokenId) public view returns (uint256[] memory _cardIndexes) {
    return _cards[_tokenId];
  }

  function balance(uint256 _tokenId, uint256 _index) public view returns (uint256 balanceAA, uint256 balanceBB) {
    require(_isCardExists(_tokenId, _index), "inexistent card");
    Card memory pos = card(_tokenId, _index);
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    return cardBalance(pos.idleCDOAddress, pos.cardAddress);
  }

  function percentage(uint256 _percentage, uint256 _amount) private pure returns (uint256) {
    require(_percentage < RATIO_PRECISION.add(1), "% should be between 0 and 1");
    return _amount.mul(_percentage).div(RATIO_PRECISION);
  }

  function _isCardExists(uint256 _tokenId, uint256 _index) internal view virtual returns (bool) {
    return _cards[_tokenId].length != 0 && _cards[_tokenId].length > _index;
  }

  function _depositToCard(
    IdleCDOCard _card,
    address _idleCDOAddress,
    uint256 _risk,
    uint256 _amount
  ) private {
    // check if _idleCDOAddress exists in idleCDOAddress array
    require(isIdleCDOListed(_idleCDOAddress), "IdleCDO address is not listed");

    IERC20Detailed underlying = IERC20Detailed(IdleCDO(_idleCDOAddress).token());

    // transfer amount to cards protocol
    underlying.safeTransferFrom(msg.sender, address(_card), _amount);

    // calculate the amount to deposit in BB
    // proportional to risk
    uint256 depositBB = percentage(_risk, _amount);

    // the amount to deposit in AA
    // inversely proportional to risk
    _card.mint(_idleCDOAddress, _amount.sub(depositBB), depositBB);
  }

  function _withdrawFromCard(uint256 _tokenId, uint256 _index) private {
    Card memory pos = card(_tokenId, _index);

    // burn the card
    (uint256 balanceAA, uint256 balanceBB) = cardBalance(pos.idleCDOAddress, pos.cardAddress);
    uint256 toRedeem = IdleCDOCard(pos.cardAddress).burn(pos.idleCDOAddress, balanceAA, balanceBB);

    // transfer to card owner
    IERC20Detailed underlying = IERC20Detailed(IdleCDO(pos.idleCDOAddress).token());
    underlying.safeTransfer(msg.sender, toRedeem);
  }

  function cardBalance(address _idleCDOAddress, address cardAddress) public view returns (uint256 balanceAA, uint256 balanceBB) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);

    balanceAA = IERC20Detailed(idleCDO.AATranche()).balanceOf(cardAddress);
    balanceBB = IERC20Detailed(idleCDO.BBTranche()).balanceOf(cardAddress);
  }

  function isIdleCDOListed(address _idleCDOAddress) private view returns (bool) {
    //TODO check gas optimization
    uint256 idleCDOsLength = idleCDOs.length;
    for (uint256 i = 0; i < idleCDOsLength; i++) {
      if (address(idleCDOs[i]) == _idleCDOAddress) {
        return true;
      }
    }
    return false;
  }
}
