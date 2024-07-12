// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

    mapping(address => uint256) public tokenIds;
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

    modifier onlyManager(uint256 serviceId) {
        require(services[serviceId].manager == msg.sender, "onlyManager");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) Ownable(msg.sender) ERC4671(_name, _symbol) {
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

    function mintPublicOrWhitelistedToken(
        address user,
        uint256 serviceId,
        bool _isPublic
    ) external {
        require(services[serviceId].active, "InactiveToken");
        ServiceStatus _status = services[serviceId].status;
        if (_isPublic) {
            require(_status == ServiceStatus.Public, "NotPublicToken");
        } else {
            require(
                _status == ServiceStatus.Whitelisted,
                "NotWhitelistedToken"
            );
            require(isWhitelisted[serviceId][user], "User Not Whitelisted");
        }
        _mintToken(user, serviceId);
    }

    function mintPrivateToken(
        address user,
        uint256 serviceId
    ) external onlyOwner {
        require(services[serviceId].active, "InactiveToken");
        require(
            services[serviceId].status == ServiceStatus.Private,
            "NotPrivateToken"
        );
        _mintToken(user, serviceId);
    }

    function mintServiceToken(
        address user,
        uint256 serviceId
    ) external onlyManager(serviceId) {
        require(services[serviceId].active, "InactiveToken");
        require(
            services[serviceId].status == ServiceStatus.Service,
            "NotServiceToken"
        );
        _mintToken(user, serviceId);
    }

    function mintPaidToken(
        address user,
        uint256 serviceId
    ) external payable onlyManager(serviceId) {
        Service memory service = services[serviceId];
        require(service.active, "InactiveToken");
        require(service.status == ServiceStatus.Paid, "NotPaidToken");
        require(service.price <= msg.value, "Insufficient Ether sent");
        _mintToken(user, serviceId);
    }

    function _mintToken(address user, uint256 serviceId) private {
        require(serviceId <= serviceCount, "Invalid Service ID");
        _mint(user);
        tokenIds[user] = emittedCount() - 1;
        setTokenURI(tokenIds[user], services[serviceId].uri);
        emit TokenMinted(user, tokenIds[user]);
    }

    function mintUniqueToken(string memory uri, address user) private {
        _mint(user);
        tokenIds[user] = emittedCount() - 1;
        setTokenURI(tokenIds[user], uri);
        emit TokenMinted(user, tokenIds[user]);
    }

    function updateWhitelist(
        address user,
        uint256 serviceId,
        bool status
    ) external onlyManager(serviceId) returns (bool) {
        isWhitelisted[serviceId][user] = status;
        return true;
    }

    function updateWhitelistBatch(
        address[] memory users,
        uint256 serviceId,
        bool status
    ) external onlyManager(serviceId) returns (bool) {
        for (uint256 i = 0; i < users.length; i++)
            isWhitelisted[serviceId][users[i]] = status;
        return true;
    }

    function updatServiceManager(
        address manager,
        uint256 serviceId
    ) external onlyOwner {
        require(serviceId <= serviceCount, "Invalid Service ID");
        services[serviceId].manager = manager;
    }

    function updatServiceURI(
        string memory uri,
        uint256 serviceId
    ) external onlyManager(serviceId) {
        require(serviceId <= serviceCount, "Invalid Service ID");
        services[serviceId].uri = uri;
    }

    function updatServiceTokenLimit(
        uint256 serviceId,
        uint64 tokenLimit
    ) external onlyManager(serviceId) {
        require(serviceId <= serviceCount, "Invalid Service ID");
        services[serviceId].tokenLimit = tokenLimit;
    }

    function updatServiceActiveStatus(
        uint256 serviceId,
        bool active
    ) external onlyManager(serviceId) {
        require(serviceId <= serviceCount, "Invalid Service ID");
        services[serviceId].active = active;
    }

    function updatServiceStatus(
        uint256 serviceId,
        ServiceStatus status
    ) external onlyManager(serviceId) {
        require(serviceId <= serviceCount, "Invalid Service ID");
        services[serviceId].status = status;
    }

    function updatServicePrice(
        uint256 serviceId,
        uint256 price
    ) external onlyManager(serviceId) {
        require(serviceId <= serviceCount, "Invalid Service ID");
        services[serviceId].price = price;
    }
}
