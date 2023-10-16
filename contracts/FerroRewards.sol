// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

// Uncomment this line to use console.log
import "hardhat/console.sol";

import {IERC20} from "./libraries/interfaces/IERC20.sol";
import {IERC721} from "./libraries/interfaces/IERC721.sol";
import {ERC20} from "./libraries/token/ERC20.sol";

import {ReentrancyGuard} from "./libraries/utils/ReentrancyGuard.sol";
import {Pausable} from "./libraries/security/Pausable.sol";
import {Ownable} from "./libraries/access/Ownable.sol";
import {BatchTransfer} from "./libraries/utils/BatchTransfer.sol";
import {Math} from "./libraries/utils/Math.sol";

contract FerroRewards is Ownable, Pausable, ReentrancyGuard {
    // State variables
    address public ironNFTContract;
    address public nickelNFTContract;
    address public cobaltNFTContract;

    // Define the airdrop parameters
    uint256 public airdropDuration; // Desired airdrop duration in hours
    uint256 public airdropInterval; // Time in hours between airdrops
    uint256 public totalAirdropCount;

    uint256 private immutable _precisionFactor = 10000;

    bool public _paused;

    // Events

    // Event to log when the contract is paused
    event PausedContract(address account);

    // Event to log when the contract is unpaused
    event UnpausedContract(address account);

    mapping(address => mapping(address => uint256)) public rewardsBalance;
    uint256 private constant _IronPercentage = 5000;
    uint256 private constant _NickelPercentage = 3000;
    uint256 private constant _CobaltPercentage = 2000;

    mapping(uint256 => address) public addresses;
    mapping(uint256 => uint256) public ironAmounts;
    mapping(uint256 => uint256) public nickelAmounts;
    mapping(uint256 => uint256) public cobaltAmounts;
    uint256 currentIndex = 0;

    // Maybe add events for airdrops?

    // Mappings to keep track of token & NFT distributions
    mapping(address => uint256) public totalTokenDistribution;

    // Array to store unique token & NFT contract addresses deposited by the owner
    address[] public depositedTokens;

    constructor(
        address _ironNFTContract,
        address _nickelNFTContract,
        address _cobaltNFTContract
    ) {
        // Initializing the NFT pools with the correct contract addresses
        ironNFTContract = _ironNFTContract;
        nickelNFTContract = _nickelNFTContract;
        cobaltNFTContract = _cobaltNFTContract;
    }

    // Receive function to allow the contract to receives Native Currency
    receive() external payable {}

    // Pause Token Trading and Transfers
    function pause() public onlyOwner {
        super._pause();
    }

    // Unpause Token Trading and Transfers
    function unpause() public onlyOwner {
        super._unpause();
    }

    function depositTokens(
        uint256 amount,
        address tokenAddress
    ) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(tokenAddress != address(0), "Invalid token address");

        IERC20 tokenToDeposit = IERC20(tokenAddress);
        require(
            tokenToDeposit.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        // Check if the token address is not already in the array
        bool exists = false;
        for (uint256 i = 0; i < depositedTokens.length; i++) {
            if (depositedTokens[i] == tokenAddress) {
                exists = true;
                break;
            }
        }

        // If the token address is not in the array, add it
        if (!exists) {
            depositedTokens.push(tokenAddress);
        }

        // Call NFT distribution for all NFT pools
        tokenDistribution(amount, tokenAddress);
    }

    // Function to distribute tokens to NFT pools based on NFT ownership
    function tokenDistribution(
        uint256 amount,
        address tokenAddress
    ) internal whenNotPaused {
        require(amount > 0, "Amount must be greater than zero");

        uint256 ironAllocation = (amount * _IronPercentage) / 10000;
        uint256 nickelAllocation = (amount * _NickelPercentage) / 10000;
        uint256 cobaltAllocation = (amount * _CobaltPercentage) / 10000;

        rewardsBalance[ironNFTContract][tokenAddress] += ironAllocation;
        rewardsBalance[nickelNFTContract][tokenAddress] += nickelAllocation;
        rewardsBalance[cobaltNFTContract][tokenAddress] += cobaltAllocation;
        // Check if the total distributed amount matches the expected total allocation
        uint256 totalAllocation = ironAllocation +
            nickelAllocation +
            cobaltAllocation;
        require(
            totalAllocation <= amount,
            "Total distribution does not match allocations"
        );
    }

    // Airdrop tokens
    function airdropTokens() external onlyOwner whenNotPaused {
        require(depositedTokens.length > 0, "No tokens available for airdrop");

        calculateAirdropAmounts(); // Calculate airdrop amounts

        // Iterate through the deposited tokens
        for (
            uint256 tokenIndex = 0;
            tokenIndex < depositedTokens.length;
            tokenIndex++
        ) {
            address tokenAddress = depositedTokens[tokenIndex];

            // Ensure there are tokens to distribute
            uint256 totalBalanceIron = rewardsBalance[ironNFTContract][
                tokenAddress
            ];
            uint256 totalBalanceNickel = rewardsBalance[nickelNFTContract][
                tokenAddress
            ];
            uint256 totalBalanceCobalt = rewardsBalance[cobaltNFTContract][
                tokenAddress
            ];

            uint256 totalAirdropIron = totalBalanceIron / totalIronNFTs;
            uint256 totalAirdropNickel = totalBalanceNickel / totalNickelNFTs;
            uint256 totalAirdropCobalt = totalBalanceCobalt / totalCobaltNFTs;

            // Iterate through the NFT pools and their respective amounts
            for (uint256 i = 0; i <= currentIndex; i++) {
                address recipient = addresses[i];
                uint256 ironNFTs = ironAmounts[i];
                uint256 nickelNFTs = nickelAmounts[i];
                uint256 cobaltNFTs = cobaltAmounts[i];

                // Calculate the distribution amount for each NFT tier
                uint256 ironDistribution = (totalAirdropIron * ironNFTs) /
                    totalAirdropCount;
                uint256 nickelDistribution = (totalAirdropNickel * nickelNFTs) /
                    totalAirdropCount;
                uint256 cobaltDistribution = (totalAirdropCobalt * cobaltNFTs) /
                    totalAirdropCount;

                uint256 totalDistribution = ironDistribution +
                    nickelDistribution +
                    cobaltDistribution;

                // Transfer tokens to the recipient
                IERC20(tokenAddress).transfer(recipient, totalDistribution);
            }
        }
    }

    // Calculate airdrop amounts for each NFT tier
    function calculateAirdropAmounts() internal {
        totalAirdropCount = airdropDuration / airdropInterval;

        airdropAmountIron = balanceOfIron / totalAirdropCount / totalIronNFTs;
        airdropAmountNickel =
            balanceOfNickel /
            totalAirdropCount /
            totalNickelNFTs;
        airdropAmountCobalt =
            balanceOfCobalt /
            totalAirdropCount /
            totalCobaltNFTs;
    }

    // Function to get the array of deposited token addresses
    function getDepositedTokens() external view returns (address[] memory) {
        return depositedTokens;
    }

    // Function to check if the contract is paused
    function isPaused() external view returns (bool) {
        return _paused;
    }
}
