// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import "@openzeppelin/contracts/access/Ownable.sol";
import "./base/ERC4671.sol";

contract JPStackerGuard is ERC4671, Ownable {
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
        require(services[_serviceId].manager == msg.sender, "onlyManager");
        _;
    }

    modifier onlyActiveService(uint256 _serviceId) {
        require(services[_serviceId].active , "InactiveToken");
        _;
    }

    modifier validServiceID(uint256 _serviceId) {
        require(_serviceId <= serviceCount, "Invalid Service ID");
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
    ) external onlyActiveService(_serviceId) {
        require(services[_serviceId].status == ServiceStatus.Public, "NotPublicToken");
        _mintToken(_user, _serviceId);
    }

    function mintWhitelistedToken(
        address _user,
        uint256 _serviceId
    ) external onlyActiveService(_serviceId) {
        require(services[_serviceId].status == ServiceStatus.Whitelisted, "NotWhitelistedToken");
        require(isWhitelisted[_serviceId][_user], "UserNotWhitelisted");
        _mintToken(_user, _serviceId);
    }
    

    function mintPrivateToken(
        address _user,
        uint256 _serviceId
    ) external onlyOwner onlyActiveService(_serviceId) {
        require(
            services[_serviceId].status == ServiceStatus.Private,
            "NotPrivateToken"
        );
        _mintToken(_user, _serviceId);
    }

    function mintServiceToken(
        address _user,
        uint256 _serviceId
    ) external onlyManager(_serviceId) onlyActiveService(_serviceId) {
        require(
            services[_serviceId].status == ServiceStatus.Service,
            "NotServiceToken"
        );
        _mintToken(_user, _serviceId);
    }

    function mintPaidToken(
        address _user,
        uint256 _serviceId
    ) external payable onlyManager(_serviceId) onlyActiveService(_serviceId) {
        require(services[_serviceId].status == ServiceStatus.Paid, "NotPaidToken");
        require(services[_serviceId].price == msg.value, "InsufficientEtherSent");
        _mintToken(_user, _serviceId);
    }

    function _mintToken(
        address _user, 
        uint256 _serviceId
    ) private {
        require(_serviceId <= serviceCount, "InvalidServiceID");
        uint256 tokenId =  _mint(_user);
        tokenIds[_user].push(tokenId);
        setTokenURI(tokenId, services[_serviceId].uri);
        emit TokenMinted(_user, tokenId);
    }

    function getUserIDs(
        address _user
    ) external view returns(uint256[] memory) {
        return tokenIds[_user];
    }

    function updateWhitelist(
        address _user,
        uint256 _serviceId,
        bool _status
    ) external onlyManager(_serviceId) returns (bool) {
        isWhitelisted[_serviceId][_user] = _status;
        return true;
    }

    function updateWhitelistBatch(
        address[] memory _users,
        uint256 _serviceId,
        bool _status
    ) external onlyManager(_serviceId) returns (bool) {
        for (uint256 i = 0; i < _users.length; i++)
            isWhitelisted[_serviceId][_users[i]] = _status;
        return true;
    }

    function updatServiceManager(
        address _manager,
        uint256 _serviceId
    ) external onlyOwner validServiceID(_serviceId) {
        services[_serviceId].manager = _manager;
    }

    function updatServiceURI(
        string memory _uri,
        uint256 _serviceId
    ) external onlyManager(_serviceId) validServiceID(_serviceId) {
        services[_serviceId].uri = _uri;
    }

    function updatServiceTokenLimit(
        uint256 _serviceId,
        uint64 _tokenLimit
    ) external onlyManager(_serviceId) validServiceID(_serviceId) {
        services[_serviceId].tokenLimit = _tokenLimit;
    }

    function updatServiceActiveStatus(
        uint256 _serviceId,
        bool _active
    ) external onlyManager(_serviceId) validServiceID(_serviceId) {
        services[_serviceId].active = _active;
    }

    function updatServiceStatus(
        uint256 _serviceId,
        ServiceStatus _status
    ) external onlyManager(_serviceId) validServiceID(_serviceId) {
        services[_serviceId].status = _status;
    }

    function updatServicePrice(
        uint256 _serviceId,
        uint256 _price
    ) external onlyManager(_serviceId) validServiceID(_serviceId) {
        services[_serviceId].price = _price;
    }
}
