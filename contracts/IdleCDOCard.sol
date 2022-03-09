// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";

contract IdleCDOCard {
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  address private manager;

  modifier onlyOwner() {
    require(msg.sender == manager, "not the card manager owner");
    _;
  }

  constructor() {
    manager = msg.sender;
  }

  function mint(address _idleCDOAddress, uint256 _amountAA, uint256 _amountBB) external onlyOwner returns (uint256 amount) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);
    
    amount = _amountAA.add(_amountBB);
  
    // approve the amount to be spend on cdos tranches
    IERC20Detailed(idleCDO.token()).approve(_idleCDOAddress, amount);

    // deposit the amount to the cdos tranches;
    idleCDO.depositAA(_amountAA);
    idleCDO.depositBB(_amountBB);
  }

  function burn(address _idleCDOAddress, uint256 balanceAA, uint256 balanceBB ) external onlyOwner returns (uint256 toRedeem) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);

    uint256 toRedeemAA = balanceAA > 0 ? idleCDO.withdrawAA(0) : 0;
    uint256 toRedeemBB = balanceBB > 0 ? idleCDO.withdrawBB(0) : 0;

    // transfers everything withdrawn to the manager
    toRedeem = toRedeemAA.add(toRedeemBB);
    IERC20Detailed(idleCDO.token()).safeTransfer(manager, toRedeem);
  }

  // This function allows you to clean up / delete contract
  function destroy() public onlyOwner {
      selfdestruct(payable(manager));
  }
}
