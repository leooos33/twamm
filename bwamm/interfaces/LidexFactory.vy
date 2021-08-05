# @version 0.2.12

contract name:
    def name(): modifying
    def name(): -> type: constant

implements: LidexFactory



interface LidexFactory:
    event PairCreated(address indexed token0, address indexed token1, address pair, uint)
    
    event PairCreated:
        token_x: indexed(address)
        token_y: indexed(address)
        pair: address
    
    @view
    @external
    def feeTo() -> address:



    function feeTo() external view returns (address)
    function feeToSetter() external view returns (address)

    function getPair(address tokenA, address tokenB) external view returns (address pair)
    function allPairs(uint) external view returns (address pair)
    function allPairsLength() external view returns (uint)

    function createPair(address tokenA, address tokenB) external returns (address pair)

    function setFeeTo(address) external
    function setFeeToSetter(address) external
