// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
  AIDynamicNFT.sol
  - Fully self-contained ERC-721 style contract
  - No imports, no constructor
  - mint() has no inputs
  - tokenURI returns on-chain generated JSON with Base64-encoded SVG image
  - Simple pure-Solidity Base64 encoder included (no inline assembly)
*/

/// @notice Simple Base64 encoder (pure-Solidity, readable)
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encode `data` to base64 string
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        uint256 len = data.length;
        // every 3 bytes become 4 chars
        uint256 encodedLen = 4 * ((len + 2) / 3);

        bytes memory result = new bytes(encodedLen);

        bytes memory table = TABLE;

        uint256 index = 0;
        for (uint256 i = 0; i < len; i += 3) {
            uint256 input = uint8(data[i]) << 16;
            if (i + 1 < len) input |= uint8(data[i + 1]) << 8;
            if (i + 2 < len) input |= uint8(data[i + 2]);

            result[index++] = table[(input >> 18) & 0x3F];
            result[index++] = table[(input >> 12) & 0x3F];
            if (i + 1 < len) {
                result[index++] = table[(input >> 6) & 0x3F];
            } else {
                result[index++] = bytes1(uint8(0x3d)); // '='
            }
            if (i + 2 < len) {
                result[index++] = table[input & 0x3F];
            } else {
                result[index++] = bytes1(uint8(0x3d)); // '='
            }
        }

        return string(result);
    }
}

contract AIDynamicNFT {
    // ERC-721-like basic state (minimal, self-contained)
    string public constant name = "AI Dynamic Art";
    string public constant symbol = "AIDA";

    uint256 private _nextTokenId;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // -------------------------
    // ERC-721 minimal interface
    // -------------------------
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "AIDA: zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "AIDA: nonexistent token");
        return o;
    }

    function approve(address to, uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), "AIDA: not owner/approved");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "AIDA: nonexistent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "AIDA: not owner nor approved");
        require(ownerOf(tokenId) == from, "AIDA: from mismatch");
        require(to != address(0), "AIDA: zero address");

        // clear approval
        _tokenApprovals[tokenId] = address(0);

        // update balances & ownership
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    // -------------------------
    // Minting (no-input mint)
    // -------------------------
    /// @notice Mint a new token to msg.sender. No inputs required.
    function mint() public {
        uint256 tokenId = _nextTokenId + 1;
        _nextTokenId = tokenId;

        address to = msg.sender;

        _owners[tokenId] = to;
        _balances[to] += 1;

        emit Transfer(address(0), to, tokenId);
    }

    // -------------------------
    // Dynamic tokenURI + on-chain SVG
    // -------------------------
    /// @notice Returns a data:application/json;base64,<...> token URI
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "AIDA: nonexistent token");

        // seed derived from tokenId, block state and owner to add variability
        bytes32 seed = keccak256(abi.encodePacked(tokenId, block.timestamp, block.number, _owners[tokenId]));

        // color from seed
        string memory color = _toColorHex(seed);

        // generate SVG
        string memory svg = _generateSVG(tokenId, color, seed);

        // base64-encode SVG and wrap
        string memory image = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));

        // metadata JSON
        string memory json = string(
            abi.encodePacked(
                '{"name":"AI Dynamic Art #',
                _uint2str(tokenId),
                '","description":"On-chain generative artwork. Metadata and image are generated dynamically from chain state.","attributes":[{"trait_type":"seed","value":"0x',
                _toShortHex(seed),
                '"}],"image":"',
                image,
                '"}'
            )
        );

        // encode JSON and return data URI
        string memory encoded = Base64.encode(bytes(json));
        return string(abi.encodePacked("data:application/json;base64,", encoded));
    }

    // -------------------------
    // SVG generator
    // -------------------------
    function _generateSVG(uint256 tokenId, string memory color, bytes32 seed) internal pure returns (string memory) {
        // derive some numbers from the seed
        uint256 rot = uint256(seed) % 360; // rotation
        uint256 x = (uint256(seed) >> 8) % 300; // position x (0..299)
        uint256 y = (uint256(seed) >> 16) % 300; // position y (0..299)
        uint256 r = 40 + (tokenId % 80); // radius

        // build svg pieces
        string memory header = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500" width="500" height="500">',
                '<defs>',
                '<radialGradient id="g" cx="50%" cy="50%" r="50%">',
                '<stop offset="0%" stop-opacity="0.9" stop-color="#',
                color,
                '"/>',
                '<stop offset="100%" stop-opacity="0.2" stop-color="#000000"/>',
                '</radialGradient>',
                '</defs>',
                '<rect width="100%" height="100%" fill="#0b0b0b"/>'
            )
        );

        string memory circle = string(
            abi.encodePacked(
                '<g transform="translate(250,250) rotate(',
                _uint2str(rot),
                ')">',
                '<circle cx="',
                _uint2str(x),
                '" cy="',
                _uint2str(y),
                '" r="',
                _uint2str(r),
                '" fill="url(#g)" fill-opacity="0.95" />',
                '</g>'
            )
        );

        string memory shapes = string(
            abi.encodePacked(
                '<g>',
                // a few decorative rectangles whose positions vary with seed
                '<rect x="20" y="20" width="80" height="8" rx="4" fill="#',
                color,
                '" opacity="0.12"/>',
                '<rect x="400" y="40" width="60" height="6" rx="3" fill="#',
                color,
                '" opacity="0.10" transform="rotate(',
                _uint2str((uint256(seed) >> 24) % 360),
                ',430,70)"/>',
                '</g>'
            )
        );

        string memory footer = string(
            abi.encodePacked(
                '<text x="250" y="485" font-family="serif" font-size="14" text-anchor="middle" fill="#ffffff">AI Dynamic Art #',
                _uint2str(tokenId),
                '</text>',
                '</svg>'
            )
        );

        return string(abi.encodePacked(header, circle, shapes, footer));
    }

    // -------------------------
    // Helpers
    // -------------------------
    // Convert bytes32 to short hex (first 8 bytes -> 16 hex chars)
    function _toShortHex(bytes32 data) internal pure returns (string memory) {
        bytes memory s = abi.encodePacked(data);
        bytes memory out = new bytes(16);
        for (uint256 i = 0; i < 8; i++) {
            uint8 b = uint8(s[i]);
            out[2 * i] = _hexChar(b >> 4);
            out[2 * i + 1] = _hexChar(b & 0x0f);
        }
        return string(out);
    }

    // Create a 6-char hex color from first 3 bytes of seed
    function _toColorHex(bytes32 data) internal pure returns (string memory) {
        bytes memory s = abi.encodePacked(data);
        bytes memory col = new bytes(6);
        for (uint256 i = 0; i < 3; i++) {
            uint8 b = uint8(s[i]);
            col[2 * i] = _hexChar(b >> 4);
            col[2 * i + 1] = _hexChar(b & 0x0f);
        }
        return string(col);
    }

    function _hexChar(uint8 nibble) internal pure returns (bytes1) {
        if (nibble < 10) return bytes1(nibble + 48); // 0..9 -> '0'..'9'
        else return bytes1(nibble + 87); // 10..15 -> 'a'..'f' (97 - 10 = 87)
    }

    // uint -> decimal string
    function _uint2str(uint256 v) internal pure returns (string memory str) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (v != 0) {
            k = k - 1;
            uint8 digit = uint8(v % 10);
            bstr[k] = bytes1(48 + digit);
            v /= 10;
        }
        return string(bstr);
    }
}
