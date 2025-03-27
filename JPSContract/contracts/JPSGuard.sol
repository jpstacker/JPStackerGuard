// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import "@openzeppelin/contracts/access/Ownable.sol";
import "./base/ERC4671.sol";

contract JPSGuard is ERC4671, Ownable {
    /* Errors */
    error JPSGuard_NotManager();
    error JPSGuard_InactiveToken();
    error JPSGuard_InvalidServiceID();
    error JPSGuard_InvalidTokenId();
    error JPSGuard_NotWhitelistedToken();
    error JPSGuard_NotWhitelisted();
    error JPSGuard_InsufficientFundsSent();
    error JPSGuard_TokenLimitExceeded();

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
        uint64 tokenLimit;
        ServiceStatus status;
        bool active;
    }

    uint256 public serviceCount;

    mapping(address => uint256[]) public tokenIds;
    mapping(uint256 => Service) public services;

    mapping(uint256 => mapping(address => bool)) public isWhitelisted;

    event ServiceRegistered(
        string uri,
        address indexed manager,
        uint256 price,
        uint256 serviceId,
        uint64 tokenLimit,
        ServiceStatus status,
        bool isPrivate
    );

    event TokenMinted(address indexed _owner, uint256 indexed _tokenId);

    modifier onlyManager(uint256 _serviceId) {
        require(services[_serviceId].manager == msg.sender, JPSGuard_NotManager());
        _;
    }

    modifier checkServiceID(uint256 _serviceId) {
        require(_serviceId <= serviceCount, JPSGuard_InvalidServiceID());
        _;
    }

    modifier checkServiceActive(uint256 _serviceId) {
        require(services[_serviceId].active , JPSGuard_InactiveToken());
        _;
    }

    modifier checkService(
        uint256 _serviceId,
        ServiceStatus _status
    ) {
        require(_serviceId <= serviceCount, JPSGuard_InvalidServiceID());
        require(services[_serviceId].manager == msg.sender, JPSGuard_NotManager());
        require(services[_serviceId].status == _status, JPSGuard_InvalidTokenId());
        _;
    }


    constructor(
        string memory _uri
    ) Ownable(msg.sender) ERC4671("JPS", "JP Stacker Guard") {
        registerServiceToken(
            _uri,
            msg.sender,
            0,
            2 ** 64 - 1,
            ServiceStatus.Public,
            true
        );
    }

    function registerServiceToken(
        string memory _uri,
        address _manager,
        uint256 _price,
        uint64 _tokenLimit,
        ServiceStatus _status,
        bool _active
    ) public onlyOwner returns (uint256) {
        serviceCount++;
        services[serviceCount] = Service(
            _uri,
            _manager,
            _price,
            _tokenLimit,
            _status,
            _active
        );
        emit ServiceRegistered(
            _uri,
            _manager,
            _price,
            serviceCount,
            _tokenLimit,
            _status,
            _active
        );
        return serviceCount;
    }

    function mintPublicToken(
        address _user,
        uint256 _serviceId
    ) 
        external 
        checkService(_serviceId, ServiceStatus.Public) 
    {
        _mintToken(_user, _serviceId);
    }  

     function mintWhitelistedToken(
        address _user,
        uint256 _serviceId
    ) 
        external 
        checkService(_serviceId, ServiceStatus.Whitelisted) 
    {
        require(isWhitelisted[_serviceId][_user], JPSGuard_NotWhitelisted());
        _mintToken(_user, _serviceId);
    }
    

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
        require(services[_serviceId].price <= msg.value, JPSGuard_InsufficientFundsSent());
        _mintToken(_user, _serviceId);
    }

    function _mintToken(
        address _user, 
        uint256 _serviceId
    ) private  {
        require(tokenIds[_user].length < services[_serviceId].tokenLimit, JPSGuard_TokenLimitExceeded());
        uint256 tokenId =  _mint(_user);
        tokenIds[_user].push(tokenId);
        setTokenURI(tokenId, services[_serviceId].uri);
        emit TokenMinted(_user, tokenId);
    }

    // function revokeToken(address _user, uint256 _tokenId) external onlyManager(_serviceIdFromToken(_tokenId)) {
    //     require(isValid(_tokenId), "Invalid token");
    //     require(ownerOf(_tokenId) == _user, "User does not own this token");
    //     _burn(_tokenId); // Assumes ERC4671 has a burn function or you implement it
    //     // Remove tokenId from tokenIds[_user] array (logic needed to handle array removal)
    //     emit TokenRevoked(_user, _tokenId);
    // }

    function getUserIDs(
        address _user
    ) external view returns(uint256[] memory) {
        return tokenIds[_user];
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
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].uri = _uri;
    }

    function updateServiceTokenLimit(
        uint256 _serviceId,
        uint64 _tokenLimit
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].tokenLimit = _tokenLimit;
    }

    function updateServiceActiveStatus(
        uint256 _serviceId,
        bool _active
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].active = _active;
    }

    function updateServiceStatus(
        uint256 _serviceId,
        ServiceStatus _status
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].status = _status;
    }

    function updateServicePrice(
        uint256 _serviceId,
        uint256 _price
    ) external onlyManager(_serviceId) checkServiceID(_serviceId) {
        services[_serviceId].price = _price;
    }
}
