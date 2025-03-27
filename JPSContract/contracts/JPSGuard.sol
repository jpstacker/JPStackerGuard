// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import "@openzeppelin/contracts/access/Ownable.sol";
import "./base/ERC4671.sol";

// Contract elements should be laid out in the following order:
// [Pragma] => [Import] => [Events] => [Errors] => [Interfaces] => [Libraries] => [Contracts]

// Inside each contract, library or interface, use the following order:
// [Type declarations] => [State variables] => [Events] => [Errors] => [Modifiers] => [Functions]

/**
 * @title JPSGuard
 * @dev JPSGuard is a smart contract that manages services and the minting of associated tokens.
 * 
 * This contract allows the owner to register different services, each of which can have its own 
 * parameters such as a price, a manager, and a status indicating its availability. Services can 
 * be public, private, service-specific, paid, or whitelisted.
 * 
 * Key features of the contract include:
 * 
 * - **Service Management**: The contract allows the owner to create and manage multiple services,
 *   each identified by a unique service ID. Each service has attributes such as:
 *   - URI for additional information.
 *   - Address of the manager responsible for the service.
 *   - Price for accessing the service (only for Paid Services).
 *   - Number of remaining tokens available for minting (If service has limited tokens).
 *   - Status indicating whether the service is public, private, etc.
 *   - Flags for limited tokens and active status.
 * 
 * - **Token Minting**: The contract provides various functions to mint tokens based on the 
 *   service's status. Tokens can be minted for:
 *   - Public access
 *   - Private access (only by the owner)
 *   - Specific services by authorized managers
 *   - Paid services, where the payment is processed and fees are handled
 *   - Whitelisted users
 * 
 * - **Whitelisting**: The contract supports a whitelisting mechanism to restrict access to certain
 *   services. Managers can update the whitelist status for users.
 * 
 * - **Error Handling**: The contract utilizes custom errors to provide efficient error handling
 *   and clear feedback when conditions are not met.
 * 
 * - **Ownership and Security**: Leveraging OpenZeppelin's Ownable contract, the owner has the
 *   authority to perform critical actions, ensuring secure management of services.
 * 
 * - **Withdrawals**: The owner can withdraw the contract's balance, ensuring control over 
 *   collected fees from paid services.
 * 
 * This contract is designed to provide a flexible framework for managing services and minting 
 * tokens while ensuring security and efficiency in interactions.
 */
contract JPSGuard is ERC4671, Ownable {
        enum ServiceStatus {
        Public,
        Private,
        Service,
        Paid,
        Whitelisted
    }

    struct Service {
        string uri;
        address manager;
        uint256 price;
        uint64 remainingTokens;
        ServiceStatus status;
        bool isLimitedToken;
        bool active;
    }

    uint256 public serviceCount;
    uint256 public immutable i_Transaction_Fee;

    mapping(address => uint256[]) public tokenIds;  // user address => token list
    mapping(uint256 => Service) public services;    // Service ID => Service Info
    mapping(uint256 => uint256) public serviceIds;  // token ID => service ID

    mapping(uint256 => mapping(address => bool)) public isWhitelisted;

    /* Events */
    event TokenMinted(address indexed _owner, uint256 indexed _tokenId);
    
    event ServiceRegistered(
        string uri,
        address indexed manager,
        uint256 price,
        uint256 indexed serviceID,
        uint64 indexed remainingTokens,
        ServiceStatus status,
        bool isLimitedToken,
        bool isPrivate
    );

    /* Errors */
    error JPSG_NotManager();
    error JPSG_NotTokenOwner();
    error JPSG_EmptyURI();
    error JPSG_InactiveToken();
    error JPSG_InvalidServiceID();
    error JPSG_InvalidTokenId();
    error JPSG_NotWhitelistedToken();
    error JPSG_NotWhitelisted();
    error JPSG_InsufficientFundsSent();
    error JPSG_TokenLimitExceeded();


    /* Modifiers */

    /**
     * @dev Modifier that checks if the caller is the manager of a specific service.
     * @param _serviceId The ID of the service to check.
     */
    modifier onlyManager(uint256 _serviceId) {
        require(services[_serviceId].manager == msg.sender, JPSG_NotManager());
        _;
    }

    /**
     * @dev Modifier that checks if a URI is non-empty.
     * @param _uri The URI to validate.
     */
    modifier nonEmptyURI(string memory _uri) {
        require(bytes(_uri).length > 0, JPSG_EmptyURI());
        _;
    }    

    /**
     * @dev Modifier that checks if the service ID is valid.
     * @param _serviceId The ID of the service to validate.
     */
    modifier checkServiceID(uint256 _serviceId) {
        require(_serviceId <= serviceCount, JPSG_InvalidServiceID());
        _;
    }

    /**
    * @dev Modifier that checks the status of a service.
    * @param _serviceId The ID of the service to check.
    * @param _status The expected status of the service.
    */
    modifier checkService(
        uint256 _serviceId,
        ServiceStatus _status
    ) {
        require(_serviceId <= serviceCount, JPSG_InvalidServiceID());
        require(services[_serviceId].active, JPSG_NotManager());
        require(services[_serviceId].status == _status, JPSG_InvalidTokenId());
        _;
    }

    /**
    * @dev Contract constructor that initializes the contract.
    * @param _uri The initial URI for the service.
    * @param _txFee The transaction fee percentage.
    */
    constructor(
        string memory _uri,
        uint8 _txFee
    ) Ownable(msg.sender) ERC4671("JPS", "JP Stacker Guard") {
        i_Transaction_Fee = _txFee;
        registerService(
            _uri,
            msg.sender,
            0,
            0,
            ServiceStatus.Public,
            false,
            true
        );
    }

    /**
    * @dev Registers a new service token.
    * @param _uri The URI for the service.
    * @param _manager The address of the service manager.
    * @param _price The price of the service.
    * @param _tokenCount The number of tokens available for the service.
    * @param _status The initial status of the service.
    * @param _isLimitedToken Indicates if the service has a token limit.
    * @param _active Indicates if the service is active.
    * @return The ID of the newly registered service.
    */
    function registerService(
        string memory _uri,
        address _manager,
        uint256 _price,
        uint64 _tokenCount,
        ServiceStatus _status,
        bool _isLimitedToken,
        bool _active
    ) public onlyOwner nonEmptyURI(_uri) returns (uint256) {
        serviceCount++;
        services[serviceCount] = Service(
            _uri,
            _manager,
            _price,
            _tokenCount,
            _status,
            _isLimitedToken,
            _active
        );
        emit ServiceRegistered(
            _uri,
            _manager,
            _price,
            serviceCount,
            _tokenCount,
            _status,
            _isLimitedToken,
            _active
        );
        return serviceCount;
    }


    /**
    * @dev Mints a token for public users.
    * @param _user The address of the user receiving the token.
    * @param _serviceId The ID of the service for which the token is minted.
    */
    function mintPublicToken(
        address _user,
        uint256 _serviceId
    ) 
        external 
        checkService(_serviceId, ServiceStatus.Public) 
    {
        _mintToken(_user, _serviceId);
    }  
    
    /**
    * @dev Mints a token for public users.
    * @param _user The address of the user receiving the token.
    * @param _serviceId The ID of the service for which the token is minted.
    */
    function mintPrivateToken(
        address _user,
        uint256 _serviceId
    ) 
        external onlyOwner 
        checkService(_serviceId, ServiceStatus.Private) 
    {
        _mintToken(_user, _serviceId);
    }

    function mintServiceToken(
        address _user,
        uint256 _serviceId
    ) 
        external 
        onlyManager(_serviceId) 
        checkService(_serviceId, ServiceStatus.Service) 
    {
        _mintToken(_user, _serviceId);
    }

    function mintPaidToken(
        address _user,
        uint256 _serviceId
    ) 
        external 
        payable 
        onlyManager(_serviceId) 
        checkService(_serviceId, ServiceStatus.Paid) 
    {
        require(services[_serviceId].price <= msg.value, JPSG_InsufficientFundsSent());

        uint256 contractFee = (msg.value * i_Transaction_Fee) / 100;
        uint256 managerAmount = msg.value - contractFee;

        _mintToken(_user, _serviceId);
        payable(msg.sender).transfer(managerAmount);
    }

    function mintWhitelistedToken(
        address _user,
        uint256 _serviceId
    ) 
        external 
        checkService(_serviceId, ServiceStatus.Whitelisted) 
    {
        require(isWhitelisted[_serviceId][_user], JPSG_NotWhitelisted());
        _mintToken(_user, _serviceId);
    }

    function _mintToken(
        address _user, 
        uint256 _serviceId
    ) private {
        if (services[_serviceId].isLimitedToken) {
            require(services[_serviceId].remainingTokens > 0, JPSG_TokenLimitExceeded());            
        }
        
        uint256 tokenId =  _mint(_user);
        services[_serviceId].remainingTokens -= 1;
        tokenIds[_user].push(tokenId);
        serviceIds[tokenId] = _serviceId;
        emit TokenMinted(_user, tokenId);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(isValid(_tokenId), JPSG_InvalidTokenId());
        return services[serviceIds[_tokenId]].uri;
    }

    function revokeToken(
        address _user, 
        uint256 _tokenId
    ) 
        external 
        onlyManager(serviceIds[_tokenId])
    { 
        require(isValid(_tokenId), JPSG_InvalidTokenId());
        require(ownerOf(_tokenId) == _user, JPSG_NotTokenOwner());
        _revoke(_tokenId);
    }

    function withdraw() 
        external 
        onlyOwner
    {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }   

    function fetchUserIDs(
        address _user,
        uint8 _start,
        uint8 _limit
    ) external view returns(uint256[] memory) {
        // return tokenIds[_user]; // Gas Intensive
        uint256[] memory ids = tokenIds[_user];
        uint256 end = _start + _limit > ids.length ? ids.length : _start + _limit;
        uint256[] memory result = new uint256[](end - _start);
        for (uint256 i = _start; i < end; i++) {
            result[i - _start] = ids[i];
        }
        return result;
    }

    function updateWhitelist(
        address _user,
        uint256 _serviceId,
        bool _status
    ) 
        external 
        onlyManager(_serviceId) 
        checkServiceID(_serviceId) 
        returns (bool) 
    {
        isWhitelisted[_serviceId][_user] = _status;
        return true;
    }

    function updateWhitelistBatch(
        address[] memory _users,
        uint256 _serviceId,
        bool _status
    ) 
        external 
        onlyManager(_serviceId) 
        checkServiceID(_serviceId) 
        returns (bool) 
    {
        for (uint256 i = 0; i < _users.length; i++)
            isWhitelisted[_serviceId][_users[i]] = _status;
        return true;
    }

    function updateServiceManager(
        address _manager,
        uint256 _serviceId
    ) external onlyOwner checkServiceID(_serviceId) {
        services[_serviceId].manager = _manager;
    }

    function updateServiceURI(
        string memory _uri,
        uint256 _serviceId
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) nonEmptyURI(_uri) {
        services[_serviceId].uri = _uri;
    }

    function updateServiceRemainingTokens(
        uint256 _serviceId,
        uint64 _tokenCount
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].remainingTokens = _tokenCount;
    }

    function updateServiceActive(
        uint256 _serviceId,
        bool _active
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].active = _active;
    }

    function updateServicePrice(
        uint256 _serviceId,
        uint256 _price
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].price = _price;
    }
}



