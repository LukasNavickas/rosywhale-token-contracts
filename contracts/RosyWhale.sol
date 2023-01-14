// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RosyWhale is ERC20, Ownable {
    constructor() ERC20("RosyWhale", "ROSY") {
        _mint(msg.sender, 450000000 * 10 ** decimals());
    }
}
