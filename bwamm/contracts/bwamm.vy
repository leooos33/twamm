# @version 0.2.12

from vyper.interfaces import ERC20

#interface UniswapV2ERC20:
#TODO

#Setup private variables

reserve0: private(int128)
reserve1: private(int128)
blockTimestampLast: private(int128)

# fixed constants
MINIMUM_LIQUIDITY: constant(uint256) = 10 ** 3

#Setup public variables
factory: public(address)
token0: public(address)
token1: public(address)

price0CumulativeLast: public(uint256)
price1CumulativeLast: public(uint256)
kLast: public(uint256)



@internal
def _update(balance0: uint256, balance1: uint256, reserve0: int128, reserve1: int128) -> bool:
    blockTimestamp: int128 = block.timestamp % (2 ** 32)
    timeElapsed: int128 = blockTimestamp - self.blockTimestampLast
    if timeElapsed > 0 and (reserve0 != 0 and reserve1 != 0):
        self.price0CumulativeLast += self.price0_cumulative_last + (reserve1 / reserve0) * timeElapsed #TODO
        self.price1CumulativeLast += self.price1_cumulative_last + (reserve0 / reserve1) * timeElapsed #TODO

    self.reserve0 = ERC20(self.token0).balanceOf(self)
    self.reserve1 = ERC20(self.token1).balanceOf(self)
    self.blockTimestampLast = blockTimestamp

    log Sync(self.reserve0, self.reserve1)

    return True

@internal
def _mintFee(_reserve0: int128, _reserve1:int128) -> bool:
    """
    @notice
    @param
    @param
    """
    feeTo: address = IUniswapV2Factory(self.factory).feeTo()
    feeOn: bool = feeTo != ZERO_ADDRESS
    
    _kLast = self.kLast

    if feeOn:
        if _kLast != 0:
            rootK: int128 = sqrt(_reserve0 * _reserve1)
            rootKLast: int128 = sqrt(_kLast)
            if rootK > rootKLast:
                numerator: uint256 = totalSupply * (rootK - rootKLast)
                denominator: uint256 = (rootK * 5) + rootKLast
                liquidity: uint256 = numerator / denominator
                if liquidity > 0:
                    _mint(feeTo, liquidity)
    elif _kLast != 0:
            self.kLast = 0
    
    return feeOn

@payable
@external
@nonreentrant('lock')
def mint(to: address) -> uint256:
    """
    @notice
    @dev
    @param to
    """
    _reserve0: uint256 = self.get_reserves()[0]
    _reserve1: uint256 = self.get_reserves()[1]
    balance0: uint256 = ERC20(self.token0).balanceOf(self)
    balance1: uint256 = ERC20(self.token1).balanceOf(self)

    amount0: uint256 = balance0 - reserve0
    amount1: uint256 = balance1 - reserve1

    feeOn: bool = _mintFee(_reserve0, _reserve1)
    _totalSupply: uint256 = totalSupply

    if _totalSupply == 0:
        liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
        _mint(ZERO_ADDRESS, MINIMUM_LIQUIDITY) #permanently lock the first MINIMUM_LIQUIDITY tokens
    else:
        liquidity = min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1)

    assert liquidity < 0, "INSUFFICIENT_LIQUIDITY_MINTED"
    _mint(to, liquidity)

    _update(balance0, balance1, _reserve0, _reserve1)

    log Mint(msg.sender, amount0, amount1)

    return liquidity

@payable
@external
@nonreentrant('lock')
def burn(to: address) -> uint256[2]:
    """
    @notice
    @dev
    @param to
    """
    balance0: uint256 = ERC20(self.token0).balanceOf(self)
    balance1: uint256 = ERC20(self.token1).balanceOf(self)
    liquidity: uint256 = balanceOf(self)

    feeOn: bool =  _mintFee(_reserve0, _reserve1)
    _totalSupply: uint256 = totalSupply

    amount0 = liquidity * balance0 / _totalSupply # using balances ensures pro-rata distribution
    amount1 = liquidity * balance1 / _totalSupply # using balances ensures pro-rata distribution
    assert amount0 < 0 and amount1 < 0, "INSUFFICIENT_LIQUIDITY_BURNED"
    _burn(self, liquidity)
    _safe_transfer(_token0, to, amount0)
    _safe_transfer(_token1, to, amount1)
    balance0 = ERC20(_token0).balanceOf(self)
    balance1 = ERC20(_token1).balanceOf(self)

    _update(balance0, balance1, _reserve0, _reserve1)
    if feeOn:
        kLast: uint256 = reserve0 * reserve1 # reserve0 and reserve1 are up-to-date
    
    log Burn(msg.sender, amount0, amount1, to)

    return [
        amount0,
        amount1
    ]


@payable
@external
@nonreentrant('lock')
def swap(amount0Out: uint256, amount1Out: uint256, to: address) -> bool:
    """

    """

@payable
@external
@nonreentrant('lock')
def place_long_term_order(_amount0In: uint256, _amount1In: uint256, to: address, block_number: int128) -> bool:
    """
    @notice
    @dev
    @param
    @param
    @param
    @param
    """
    assert block_number <= block.number and (to == token0 and to == token1) 
    assert block_number - block.number >= 250 

    if amount0In > 0:
        index: int128 = self.nextOrderindex0
        amount0PerBlock: int128 = _amount0In / (block_number - block.number)
        self.orders0[index] = LongTermOrder0({sender: msg.sender, xStart: self.reserve0, yStart: self.reserve1, amount0In: _amount0In})
         #записать индекс, текущий х и у, блок окончания и кол-во за блок
    sender: address
    xStart: int128
    yStart: int128
    amount0In: int128
    amount0PerBlock: int128
    orderExpiration: int128

    return True



@payable
@external
@nonreentrant('lock')
def skim() -> bool:
    """
    @notice Force balances to match reserves
    """
    _safeTransfer(_token0, to, ERC20(_token0).balanceOf(self) - reserve0)
    _safeTransfer(_token0, to, ERC20(_token1).balanceOf(self) - reserve1)

    return True

@payable
@external
@nonreentrant('lock')
def sync() -> bool:
    """
    @notice Force reserves to match balances
    """
    _update(ERC20(token0).balanceOf(self), ERC20(token1).balanceOf(self), reserve0, reserve1)

    return True