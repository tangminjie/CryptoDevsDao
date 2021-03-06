// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import {Errors} from './libraries/Errors.sol';

contract Whitelist is Ownable,VRFConsumerBase,AccessControlEnumerable,Pausable{

    struct WhitelistData{
        // Max number of whitelisted addresses allowed
        uint8 maxWhitelisteNumIssued;
        address[] whilteListIssued;
        // Create a mapping of whitelistedAddresses
        // if an address is whitelisted, we would set it to true, it is false by default for all other addresses.
        mapping(address => bool) whitelistedAddresses;
        address [] NumTowhitelistedAddresses;
        // numAddressesWhitelisted would be used to keep track of how many addresses have been whitelisted
        uint256 numAddressesWhitelisted;
    }

    struct ChainLinkData{
        uint256 seed;
        //Get a Random Number
        bytes32 keyHash;
        uint256 fee;
    }

    /// @dev keccak256('INVITER_ROLE')
    bytes32 public constant INVITER_ROLE =
        0x639cc15674e3ab889ef8ffacb1499d6c868345f7a98e2158a7d43d23a757f8e0;
      /// @dev keccak256('PAUSER_ROLE')
    bytes32 public constant PAUSER_ROLE =
        0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a;

    WhitelistData public whitelistData;
    ChainLinkData private chainLinkData;

    // Setting the Max number of whitelisted addresses
    // User will put the value at the time of deployment
    constructor(uint8 _maxWhitelistedAddresses,address msgSender) payable VRFConsumerBase(
            0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B, // VRF Coordinator
            0x01BE23585060835E02B77ef475b0Cc51aA1e0709  // LINK Token
        ){
        whitelistData.maxWhitelisteNumIssued =  _maxWhitelistedAddresses;
        console.log("maxWhitelistedAddresses [%d]!",whitelistData.maxWhitelisteNumIssued);

        _grantRole(INVITER_ROLE, msgSender);
        _grantRole(PAUSER_ROLE,  msgSender);
        /*
            init seed 
        */
        chainLinkData.seed = (block.timestamp + block.difficulty) % 100;
        chainLinkData.keyHash = 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;
        chainLinkData.fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
        console.log("init seed:",chainLinkData.seed);
       // getRandomNumber();
    }

    /**
        addAddressToWhitelist - This function adds the address of the sender to the
        whitelist
    */
    function addAddressToWhitelist(address whiteAddress) external {
        // check if the user has already been whitelisted
        require(!whitelistData.whitelistedAddresses[whiteAddress], "Sender has already been whitelisted");
        // Add the address which called the function to the whitelistedAddress array
        whitelistData.whitelistedAddresses[whiteAddress] = false;
        whitelistData.NumTowhitelistedAddresses.push(whiteAddress);
        // Increase the number of whitelisted addresses
        whitelistData.numAddressesWhitelisted += 1;
    }

    struct Random {
        address addr; 
        uint256 rand; 
        bool isRet; 
    }

    mapping(bytes32 => Random) public requestIdToRandomNumber;
    mapping(address => bytes32) public AddressTorequestId;
    
    /** 
     * Requests randomness 
     */
    function getRandomNumber() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= chainLinkData.fee, "Not enough LINK - fill contract with faucet");
        bytes32 Id = requestRandomness(chainLinkData.keyHash, chainLinkData.fee);
        requestIdToRandomNumber[Id].addr = msg.sender;
        requestIdToRandomNumber[Id].isRet = false;
        AddressTorequestId[msg.sender] = Id;
        return Id;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        requestIdToRandomNumber[requestId].rand = randomness;
        requestIdToRandomNumber[requestId].isRet = true;
        console.log("fulfillRandomness randomness is [%d].!",randomness);
    }

    function expand(uint256 randomValue, uint256 n) private view returns (uint256[] memory ) {
        uint256[] memory expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(randomValue, i))) % whitelistData.numAddressesWhitelisted;
        }
        return expandedValues;
    }

    function getALLWhiteListData() external view onlyOwner returns (address[] memory){
        return whitelistData.NumTowhitelistedAddresses;
    }

    function getALLWhiteListNum() external view returns (uint256) {
        return whitelistData.numAddressesWhitelisted;
    }

    /**
     * @dev - get whitelist num if the whitelistmaxnum more than the num ,Draw a lottery on the random number of the water machine
     * @param - num need whitelist num;
     */
    function getWhilteListIssued(uint256 num) external onlyOwner returns (address[] memory ){
        if(whitelistData.numAddressesWhitelisted < whitelistData.maxWhitelisteNumIssued){
            return whitelistData.NumTowhitelistedAddresses;
        }
        else{
            require(requestIdToRandomNumber[AddressTorequestId[msg.sender]].isRet == true, "random is not ready!!");
            //Generate num random numbers for Chainlink random
            uint256[] memory randomArrays = expand(requestIdToRandomNumber[AddressTorequestId[msg.sender]].rand,num);
            for(uint i=0;i<randomArrays.length;i++){
                address WhilteListAddress =  whitelistData.NumTowhitelistedAddresses[randomArrays[i]];
                whitelistData.whilteListIssued.push(WhilteListAddress);
                whitelistData.whitelistedAddresses[WhilteListAddress] = true;
            }  
            return whitelistData.whilteListIssued;
        }
    }

    //
    //use merkle for whitelist
    bytes32 private _merkleTreeRoot;

    /**
     * @dev update whitelist by a back-end server bot
     */
    function updateWhitelist(bytes32 merkleTreeRoot_) external {
        if (!hasRole(INVITER_ROLE, _msgSender())) revert Errors.NotInviter();

        _merkleTreeRoot = merkleTreeRoot_;
    }

    function checkMerkleTreeRootForWhitelist(bytes32[] calldata proof,address leaf) external view returns (bool){
       
        if (!MerkleProof.verify(proof, _merkleTreeRoot, keccak256(abi.encodePacked(leaf))))
            return false;
        else
            return true;
    }

    function pause() public {
        if (!hasRole(PAUSER_ROLE, _msgSender())) revert Errors.NotPauser();

        _pause();
    }

    function unpause() public {
        if (!hasRole(PAUSER_ROLE, _msgSender())) revert Errors.NotPauser();

        _unpause();
    }
}