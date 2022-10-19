pragma solidity ^0.8.16;

interface WardsLike {
    function rely(address usr) external;

    function deny(address usr) external;

    function wards(address usr) external view returns (uint256);
}

interface CanLike {
    function hope(address usr) external;

    function nope(address usr) external;

    function can(address usr) external view returns (uint256);
}

interface FileLike {
    function file(bytes32 what, address data) external;
}

contract Safebox is WardsLike, CanLike, FileLike {
    mapping(address => uint256) public wards;

    mapping(address => uint256) public can;

    address public recipient;

    address public pendingRecipient;

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event Hope(address indexed usr);
    event Nope(address indexed usr);

    event File(bytes32 indexed what, address data);

    event RecipientChange(address indexed recipient);

    modifier auth() {
        require(wards[msg.sender] == 1, "Safebox/not-authorized");
        _;
    }

    constructor(
        address _owner,
        address _custodian,
        address _recipient
    ) {
        wards[_owner] = 1;
        emit Rely(_owner);

        can[_custodian] = 1;
        emit Hope(_custodian);

        recipient = _recipient;
        emit RecipientChange(_recipient);
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function hope(address usr) external auth {
        can[usr] = 1;
        emit Hope(usr);
    }

    function nope(address usr) external auth {
        can[usr] = 0;
        emit Nope(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "recipient") {
            pendingRecipient = data;
            emit File(what, data);
        } else {
            revert("Safebox/file-unrecognized-param");
        }
    }

    function approveChangeRecipient(address _recipient) external {
        require(can[msg.sender] == 1, "Safebox/not-allowed");
        require(pendingRecipient != address(0) && pendingRecipient == _recipient, "Safebox/recipient-mismatch");

        recipient = _recipient;
        pendingRecipient = address(0);

        emit RecipientChange(_recipient);
    }

    function deposit(address token, uint256 amount) external auth {
        _safeTransferFrom(token, msg.sender, address(this), amount);
    }

    function withdraw(address token, uint256 amount) external auth {
        _safeTransfer(token, recipient, amount);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSelector(ERC20Like(address(0)).transferFrom.selector, from, to, amount)
        );
        require(
            success && (result.length == 0 || abi.decode(result, (bool))),
            "Safebox/token-transfer-from-failed"
        );
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory result) = token.call(
            abi.encodeWithSelector(ERC20Like(address(0)).transfer.selector, to, amount)
        );
        require(success && (result.length == 0 || abi.decode(result, (bool))), "Safebox/token-transfer-failed");
    }
}

interface ERC20Like {
    function transfer(address to, uint256 amt) external returns (bool);

    function transferFrom(address from, address to, uint256 amt) external returns (bool);

    function balanceOf(address usr) external view returns (uint256);
}
