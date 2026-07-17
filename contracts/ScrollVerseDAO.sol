// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * ╔════════════════════════════════════════════════════════════════╗
 * ║         SCROLLVERSE DAO GOVERNANCE                            ║
 * ║         144 Passport Voting Weight                            ║
 * ║         Hero vs Adversary Friction = Maximum Yield            ║
 * ║         963Hz Baseline • Immutable Ledger                     ║
 * ╚════════════════════════════════════════════════════════════════╝
 */

// ============================================================================
// PASSPORT NFT — VOTING POWER ANCHOR
// ============================================================================

contract ScrollVersePassport is ERC721, ERC721Enumerable, ERC721Votes, Ownable {
    uint256 private _nextTokenId;
    
    // Passport metadata
    struct PassportMetadata {
        string variant; // "Hero" or "Adversary"
        uint256 votingWeight; // 1-10 based on tier
        uint256 mintedAt;
        string frequency; // "963Hz", "528Hz", "852Hz"
        bool isActive;
    }
    
    mapping(uint256 => PassportMetadata) public passportData;
    
    // Variant tracking for friction calculation
    uint256 public heroCount;
    uint256 public adversaryCount;
    
    // Frequency alignment
    string public constant BASELINE_FREQUENCY = "963Hz";
    
    event PassportMinted(uint256 indexed tokenId, address indexed to, string variant, uint256 votingWeight);
    event VariantFrictionCalculated(uint256 heroCount, uint256 adversaryCount, uint256 yieldMultiplier);

    constructor() ERC721("ScrollVersePassport", "SVPASS") ERC721Permit("ScrollVersePassport") {}

    /**
     * Mint Passport with variant and voting weight
     */
    function mintPassport(
        address to,
        string memory variant,
        uint256 votingWeight
    ) public onlyOwner returns (uint256) {
        require(votingWeight >= 1 && votingWeight <= 10, "Invalid voting weight");
        require(
            keccak256(abi.encodePacked(variant)) == keccak256(abi.encodePacked("Hero")) ||
            keccak256(abi.encodePacked(variant)) == keccak256(abi.encodePacked("Adversary")),
            "Invalid variant"
        );

        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _delegate(to, to);

        passportData[tokenId] = PassportMetadata({
            variant: variant,
            votingWeight: votingWeight,
            mintedAt: block.timestamp,
            frequency: BASELINE_FREQUENCY,
            isActive: true
        });

        if (keccak256(abi.encodePacked(variant)) == keccak256(abi.encodePacked("Hero"))) {
            heroCount++;
        } else {
            adversaryCount++;
        }

        emit PassportMinted(tokenId, to, variant, votingWeight);
        _calculateFrictionYield();

        return tokenId;
    }

    /**
     * Calculate friction yield from Hero vs Adversary tension
     */
    function _calculateFrictionYield() internal {
        if (heroCount > 0 && adversaryCount > 0) {
            uint256 frictionRatio = (heroCount * 100) / (adversaryCount + 1);
            uint256 yieldMultiplier = (frictionRatio > 100) ? (frictionRatio / 100) : 1;
            
            emit VariantFrictionCalculated(heroCount, adversaryCount, yieldMultiplier);
        }
    }

    /**
     * Get voting weight for a passport
     */
    function getVotingWeight(uint256 tokenId) public view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return passportData[tokenId].votingWeight;
    }

    /**
     * Get total voting power for an address
     */
    function getTotalVotingPower(address account) public view returns (uint256) {
        uint256 totalPower = 0;
        uint256 balance = balanceOf(account);
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(account, i);
            totalPower += getVotingWeight(tokenId);
        }
        
        return totalPower;
    }

    /**
     * Get passport metadata
     */
    function getPassportData(uint256 tokenId) public view returns (PassportMetadata memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return passportData[tokenId];
    }

    // Required overrides
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Votes)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Votes)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

// ============================================================================
// SCROLLVERSE DAO GOVERNOR
// ============================================================================

contract ScrollVerseDAO is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    ScrollVersePassport public passportNFT;
    
    // DAO parameters
    uint256 public constant VOTING_DELAY = 1; // 1 block
    uint256 public constant VOTING_PERIOD = 50400; // 1 week
    uint256 public constant PROPOSAL_THRESHOLD = 1; // 1 passport
    uint256 public constant QUORUM_PERCENTAGE = 10; // 10%
    
    // Proposal tracking
    struct ProposalData {
        uint256 proposalId;
        string title;
        string description;
        uint256 heroVotes;
        uint256 adversaryVotes;
        string status; // "Pending", "Active", "Defeated", "Succeeded", "Executed"
    }
    
    mapping(uint256 => ProposalData) public proposalRegistry;
    uint256[] public allProposals;
    
    // Frequency alignment
    string public constant BASELINE_FREQUENCY = "963Hz";
    uint256 public frequencyPulse = 963;
    
    event ProposalCreatedWithFriction(uint256 indexed proposalId, string title, uint256 heroVotes, uint256 adversaryVotes);
    event FrequencyPulseUpdated(uint256 newPulse);

    constructor(ScrollVersePassport _passportNFT)
        Governor("ScrollVerseDAO")
        GovernorSettings(
            VOTING_DELAY,     // 1 block
            VOTING_PERIOD,    // 1 week
            PROPOSAL_THRESHOLD // 1 passport
        )
        GovernorVotes(_passportNFT)
        GovernorVotesQuorumFraction(QUORUM_PERCENTAGE)
    {
        passportNFT = _passportNFT;
    }

    /**
     * Create proposal with friction tracking
     */
    function proposeWithFriction(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory title,
        string memory description
    ) public returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);
        
        // Track proposal
        proposalRegistry[proposalId] = ProposalData({
            proposalId: proposalId,
            title: title,
            description: description,
            heroVotes: 0,
            adversaryVotes: 0,
            status: "Pending"
        });
        
        allProposals.push(proposalId);
        
        emit ProposalCreatedWithFriction(proposalId, title, 0, 0);
        
        return proposalId;
    }

    /**
     * Cast vote with variant tracking
     */
    function castVoteWithVariant(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        uint256[] calldata passportTokenIds
    ) public returns (uint256) {
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < passportTokenIds.length; i++) {
            uint256 tokenId = passportTokenIds[i];
            require(passportNFT.ownerOf(tokenId) == _msgSender(), "Not passport owner");
            
            ScrollVersePassport.PassportMetadata memory data = passportNFT.getPassportData(tokenId);
            totalWeight += data.votingWeight;
            
            // Track by variant
            if (keccak256(abi.encodePacked(data.variant)) == keccak256(abi.encodePacked("Hero"))) {
                proposalRegistry[proposalId].heroVotes += data.votingWeight;
            } else {
                proposalRegistry[proposalId].adversaryVotes += data.votingWeight;
            }
        }
        
        return castVoteWithReasonAndParams(_msgSender(), proposalId, support, reason, "");
    }

    /**
     * Get proposal friction data
     */
    function getProposalFriction(uint256 proposalId) public view returns (uint256 heroVotes, uint256 adversaryVotes, uint256 frictionYield) {
        ProposalData memory data = proposalRegistry[proposalId];
        uint256 yield = 0;
        
        if (data.heroVotes > 0 && data.adversaryVotes > 0) {
            yield = (data.heroVotes * data.adversaryVotes) / 100; // Friction = Hero × Adversary
        }
        
        return (data.heroVotes, data.adversaryVotes, yield);
    }

    /**
     * Update frequency pulse
     */
    function updateFrequencyPulse(uint256 newPulse) public onlyGovernance {
        frequencyPulse = newPulse;
        emit FrequencyPulseUpdated(newPulse);
    }

    /**
     * Get all proposals
     */
    function getAllProposals() public view returns (uint256[] memory) {
        return allProposals;
    }

    /**
     * Get proposal count
     */
    function getProposalCount() public view returns (uint256) {
        return allProposals.length;
    }

    // Required overrides
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor)
        returns (bool)
    {
        return false;
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash,
        address executor
    ) internal override(Governor) {
        super._execute(targets, values, calldatas, descriptionHash, executor);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash,
        address executor
    ) internal override(Governor) returns (uint48) {
        return super._cancel(targets, values, calldatas, descriptionHash, executor);
    }

    function _executor()
        internal
        view
        override(Governor)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

/**
 * ╔════════════════════════════════════════════════════════════════╗
 * ║         DEPLOYMENT GUIDE                                      ║
 * ║                                                                ║
 * ║ 1. Deploy ScrollVersePassport                                 ║
 * ║ 2. Deploy ScrollVerseDAO with Passport address                ║
 * ║ 3. Mint 144 Passports (72 Hero, 72 Adversary)                ║
 * ║ 4. Distribute to Verified Sovereigns                          ║
 * ║ 5. Activate governance voting                                 ║
 * ║                                                                ║
 * ║ VOTING WEIGHT DISTRIBUTION:                                   ║
 * ║ - Tier 1 (Founder): 10 weight per passport                   ║
 * ║ - Tier 2 (Architect): 5 weight per passport                  ║
 * ║ - Tier 3 (Guardian): 3 weight per passport                   ║
 * ║ - Tier 4 (Sovereign): 1 weight per passport                  ║
 * ║                                                                ║
 * ║ FRICTION YIELD:                                               ║
 * ║ Hero Votes × Adversary Votes = Governance Yield               ║
 * ║ Maximum yield when votes are balanced (72-72)                 ║
 * ║                                                                ║
 * ║ KUN FAYAKŪN × ∞ × ∞ × ∞                                        ║
 * ╚════════════════════════════════════════════════════════════════╝
 */
