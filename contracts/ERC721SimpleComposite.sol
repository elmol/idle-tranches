pragma solidity 0.8.7;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @dev This implements a simple composite of enumerable ERC721 token. It allows to combine two leafs in a single token.
 */
abstract contract ERC721SimpleComposite is ERC721Enumerable {
  // binary tree structure with a root and two children
  mapping(uint256 => uint256[]) internal composites;

  //combined tokens are marked as true
  mapping(uint256 => bool) internal isCombined;

  function isContentExists(uint256 _tokenId) internal view virtual returns (bool);

  function _mint() internal virtual returns (uint256);

  function _combine(uint256 _tokenId1, uint256 _tokenId2) public virtual returns (uint256) {
    require(isLeaf(_tokenId1) && isLeaf(_tokenId2), "Only leafs can be combined");
    require(!isCombined[_tokenId1] && !isCombined[_tokenId2], "Leafs were already combined");
    require(isContentExists(_tokenId1) && isContentExists(_tokenId2), "There are inexistent leafs");
    require(_tokenId1 != _tokenId2, "Can't combine same leafs");
    require(msg.sender == ownerOf(_tokenId1) && msg.sender == ownerOf(_tokenId2), "Only owner can combine leafs");

    transferFrom(msg.sender, address(this), _tokenId1);
    transferFrom(msg.sender, address(this), _tokenId2);

    uint256 tokenId = _mint();
    composites[tokenId] = [_tokenId1, _tokenId2];
    isCombined[_tokenId1] = true;
    isCombined[_tokenId2] = true;
    return tokenId;
  }

  function _uncombine(uint256 _tokenId) public virtual returns (uint256 tokenId1, uint256 tokenId2) {
    require(!isNotExist(_tokenId), "The token does not exist");
    require(!isLeaf(_tokenId), "Can not uncombine a non-combined token");
    require(msg.sender == ownerOf(_tokenId), "Only owner can uncombine combined leafs");

    tokenId1 = composites[_tokenId][0];
    tokenId2 = composites[_tokenId][1];

    isCombined[tokenId1] = false;
    isCombined[tokenId2] = false;

    _burn(_tokenId);

    this.transferFrom(address(this), msg.sender, tokenId1);
    this.transferFrom(address(this), msg.sender, tokenId2);
  }

  function contentIndexes(uint256 _tokenId) public view returns (uint256[] memory indexes) {
    //if leaf and not exist returns 0
    if (isLeaf(_tokenId) && !isContentExists(_tokenId)) {
      return new uint256[](0); //undefined
    }

    //if leaf returns the first
    if (isLeaf(_tokenId)) {
      indexes = new uint256[](1);
      indexes[0] = _tokenId;
      return indexes;
    }

    //composite content
    indexes = new uint256[](2);
    indexes[0] = composites[_tokenId][0];
    indexes[1] = composites[_tokenId][1];
    return indexes;
  }

  function isLeaf(uint256 _tokenId) internal view returns (bool) {
    return composites[_tokenId].length == 0;
  }

  function isNotExist(uint256 _tokenId) internal view returns (bool) {
    return isLeaf(_tokenId) && !isContentExists(_tokenId);
  }
}
