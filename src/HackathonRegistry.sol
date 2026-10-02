// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Swarm Spark hackathon entry registry
/// @notice One permanent entry ID per address; metadata edits close 14 days after deployment.
/// @dev No owner, external calls, token dependency, payments or upgrade path.
contract HackathonRegistry {
    uint256 public constant DURATION = 14 days;
    uint256 public constant MAX_NAME_BYTES = 64;
    uint256 public constant MAX_URL_BYTES = 200;
    uint256 public constant TOOLKIT_COUNT = 19;
    uint256 public constant VALID_TOOLKIT_MASK = (1 << TOOLKIT_COUNT) - 1;

    /// @notice The prize wallet is ineligible. This address receives no authority or funds here.
    address public constant ORGANISER = 0x9e134c3dedDb698B81C9E1581925766b62d26400;

    /// @notice Registration and updates require block.timestamp strictly less than this value.
    uint256 public immutable deadline;

    struct Entry {
        address entrant;
        string projectName;
        string repositoryUrl;
        string demoUrl;
        uint256 toolkitMask;
        bool withdrawn;
    }

    /// @notice Total historical registrations, including withdrawals. IDs are 1 through entryCount.
    uint256 public entryCount;
    /// @notice Zero means never registered. The ID remains assigned after withdrawal.
    mapping(address entrant => uint256 id) public entryIdOf;
    mapping(uint256 id => Entry entry) private _entries;

    error RegistrationClosed();
    error OrganiserIneligible();
    error AlreadyRegistered();
    error NotRegistered();
    error EntryAlreadyWithdrawn();
    error InvalidEntryId();
    error InvalidNameLength();
    error InvalidRepositoryUrlLength();
    error InvalidDemoUrlLength();
    error InvalidToolkitMask();

    event RegistryOpened(uint256 deadline);
    event EntryRegistered(
        uint256 indexed id,
        address indexed entrant,
        string projectName,
        string repositoryUrl,
        string demoUrl,
        uint256 toolkitMask
    );
    event EntryUpdated(
        uint256 indexed id,
        address indexed entrant,
        string projectName,
        string repositoryUrl,
        string demoUrl,
        uint256 toolkitMask
    );
    event EntryWithdrawn(uint256 indexed id, address indexed entrant);

    constructor() {
        deadline = block.timestamp + DURATION;
        emit RegistryOpened(deadline);
    }

    modifier whileOpen() {
        if (block.timestamp >= deadline) revert RegistrationClosed();
        _;
    }

    /// @notice Register the caller once. URLs are untrusted metadata; availability is checked off-chain.
    /// @param toolkitMask Nonzero combination of bits 0 through 18, as defined in docs/toolkit.md.
    function register(
        string calldata projectName,
        string calldata repositoryUrl,
        string calldata demoUrl,
        uint256 toolkitMask
    ) external whileOpen returns (uint256 id) {
        if (msg.sender == ORGANISER) revert OrganiserIneligible();
        if (entryIdOf[msg.sender] != 0) revert AlreadyRegistered();
        _validate(projectName, repositoryUrl, demoUrl, toolkitMask);

        id = ++entryCount;
        entryIdOf[msg.sender] = id;
        _entries[id] = Entry(msg.sender, projectName, repositoryUrl, demoUrl, toolkitMask, false);
        emit EntryRegistered(id, msg.sender, projectName, repositoryUrl, demoUrl, toolkitMask);
    }

    /// @notice Replace the caller's metadata before the deadline. Withdrawn entries cannot be edited.
    function update(
        string calldata projectName,
        string calldata repositoryUrl,
        string calldata demoUrl,
        uint256 toolkitMask
    ) external whileOpen {
        uint256 id = _activeEntryId();
        _validate(projectName, repositoryUrl, demoUrl, toolkitMask);

        Entry storage entry = _entries[id];
        entry.projectName = projectName;
        entry.repositoryUrl = repositoryUrl;
        entry.demoUrl = demoUrl;
        entry.toolkitMask = toolkitMask;
        emit EntryUpdated(id, msg.sender, projectName, repositoryUrl, demoUrl, toolkitMask);
    }

    /// @notice Permanently withdraw the caller's entry at any time, including after the deadline.
    /// @dev Metadata and ID are preserved for historical enumeration; no re-registration is possible.
    function withdraw() external {
        uint256 id = _activeEntryId();
        _entries[id].withdrawn = true;
        emit EntryWithdrawn(id, msg.sender);
    }

    /// @notice Read a stable ID in [1, entryCount], including withdrawn entries.
    function getEntry(uint256 id) external view returns (Entry memory) {
        if (id == 0 || id > entryCount) revert InvalidEntryId();
        return _entries[id];
    }

    function _activeEntryId() private view returns (uint256 id) {
        id = entryIdOf[msg.sender];
        if (id == 0) revert NotRegistered();
        if (_entries[id].withdrawn) revert EntryAlreadyWithdrawn();
    }

    function _validate(
        string calldata projectName,
        string calldata repositoryUrl,
        string calldata demoUrl,
        uint256 toolkitMask
    ) private pure {
        if (bytes(projectName).length == 0 || bytes(projectName).length > MAX_NAME_BYTES) {
            revert InvalidNameLength();
        }
        if (bytes(repositoryUrl).length == 0 || bytes(repositoryUrl).length > MAX_URL_BYTES) {
            revert InvalidRepositoryUrlLength();
        }
        if (bytes(demoUrl).length == 0 || bytes(demoUrl).length > MAX_URL_BYTES) revert InvalidDemoUrlLength();
        if (toolkitMask == 0 || toolkitMask > VALID_TOOLKIT_MASK) revert InvalidToolkitMask();
    }
}
