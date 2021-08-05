# @version 0.2.12

from vyper.interfaces import ERC20

interface LidexERC20:
    def mint(_to: address, _value: uint256) -> bool: nonpayable
    def burn(_to: address, _value: uint256) -> bool: nonpayable 
    def totalSupply() -> uint256: view

#Setup private variables
reserve_x: uint256
reserve_y: uint256
blockTimestampLast: uint256

# fixed constants
MINIMUM_LIQUIDITY: constant(uint256) = 10 ** 3

#Setup public variables
factory: public(address)
token_x: public(address)
token_y: public(address)
lp_token: public(address)

last_synced_block: uint256
last_synced_index: uint256

# <--- LongTermOrders0 --->

struct LongTermOrderX:
    start: uint256               # order initiation block number
    x_start: uint256             # x_ammStart
    y_start: uint256             # y_ammStart
    amount_x_in: uint256         # x_in
    amount_x_per_block: uint256  # amount0_in / (expiration block - initiation block)

nestedMapX: HashMap[uint256, HashMap[address, LongTermOrderX]] # block, sender address, orderData
# dev Only one order is allowed from the address per expiration block

struct DoubleLinkedList:
    expiration_block: uint256
    per_block: uint256
    prev_block: uint256
    next_block: uint256

perBlockX: HashMap[uint256, DoubleLinkedList] # index + struct(block, per_block, links to nodes)

# <--- LongTermOrdersY --->

struct LongTermOrderY:
    start: uint256
    x_start: uint256
    y_start: uint256
    amount_y_in: uint256
    amount_y_per_block: uint256

nestedMapY: HashMap[uint256, HashMap[address, LongTermOrderY]] 

perBlockY: HashMap[uint256, DoubleLinkedList] # same DoubleLinkedList struct, no need to create one more

head: uint256

price_x_cumulative_last: public(uint256)
price_y_cumulative_last: public(uint256)
k_last: public(uint256)

# <--- Events --->

event Mint:
    sender: indexed(address)
    amount_x: uint256
    amount_y: uint256

event Burn:
    sender: indexed(address)
    amount_x: uint256
    amount_y: uint256
    to: indexed(address)

event Swap:
    sender: indexed(address)
    amount_x_in: uint256
    amount_y_in: uint256
    amount_x_out: uint256
    amount_y_out: uint256
    to: indexed(address)

event Sync:
    reserveX: uint256
    reserveY: uint256

event NewLongTermOrderX:
    sender: address
    start: uint256
    x_start: uint256
    y_start: uint256
    amount_x_in: uint256
    amount_x_per_block: uint256
    orderExpiration: uint256

event NewLongTermOrderY:
    sender: address
    start: uint256
    x_start: uint256
    y_start: uint256
    amount_y_in: uint256
    amount_y_per_block: uint256
    orderExpiration: uint256

# mb it should be only one event 

event CancelLongTermOrder:
    #TODO
    sender: address
    block_n: uint256
    amount_y_in: uint256
    amount_y_per_block: uint256

@external
def __init__(
    _token_x: address,
    _token_y: address,
    _lp_token: address
    ):
    """
    @notice Contract constructor
    @dev    Should be called by the factory
    @param  _token_x ERC20 token address
    @param  _token_y ERC20 token address
    """
    assert msg.sender == self.factory, "FORBIDDEN"

    self.factory = msg.sender
    self.token_x = _token_x
    self.token_y = _token_y
    self.lp_token = _lp_token
    self.last_synced_block = block.number
    self.last_synced_index = 0

# <--- ERC20 Safe Transfer --->

@internal
def _safe_transfer(_token: address, _to: address, _value: uint256) -> bool:
    """
    @notice OpenZeppelin "safeTransfer" Vyper implementation
    @param  _token ERC20 token address
    @param  _to Recipient address
    @param _value Amount to transfer
    @return bool or not
    """
    _response: Bytes[32] = raw_call(
        _token,
        concat(
            method_id("transfer(address,uint256)"),
            convert(_to, bytes32),
            convert(_value, bytes32)
        ),
        max_outsize = 32
    )
    if len(_response) > 0:
        assert convert(_response, bool), "TRANSFER_FAILED"

    return True

# <--- Get functions --->
@internal
def _get_reserves() -> uint256[3]:
    """
    @notice Return reserves of token0 and token1 with the last block timestamp.
    """
    #TODO Calculate current reserves with account for x_in and y_in 
    #last_synced_block: uint256 = self.last_synced_block
    #last_synced_index: uint256 = self.last_synced_index


    #self.last_synced_block = block.number

    return [
        self.reserve_x,
        self.reserve_y,
        self.blockTimestampLast
    ]


@internal
def _update(balance_x: uint256, balance_y: uint256, reserve_x: uint256, reserve_y: uint256) -> bool:
    """
    @notice
    @dev
    @param
    @param
    @param
    @param
    """
    blockTimestamp: uint256 = block.timestamp % (2 ** 32)
    timeElapsed: uint256 = blockTimestamp - self.blockTimestampLast

    if timeElapsed > 0 and (reserve_x != 0 and reserve_y != 0):
        self.price_x_cumulative_last += self.price_x_cumulative_last + (reserve_y / reserve_x) * timeElapsed #TODO
        self.price_y_cumulative_last += self.price_y_cumulative_last + (reserve_x / reserve_y) * timeElapsed #TODO

    self.reserve_x = ERC20(self.token_x).balanceOf(self)
    self.reserve_y = ERC20(self.token_y).balanceOf(self)
    self.blockTimestampLast = blockTimestamp

    log Sync(self.reserve_x, self.reserve_y)

    return True

@internal
def _mintFee(_reserve_x: uint256, _reserve_y: uint256, lp_token: address) -> bool:
    """
    @notice
    @param
    @param
    """
    feeTo: address = self.factory       
    feeOn: bool = feeTo != ZERO_ADDRESS
    
    _k_last: uint256 = self.k_last

    if feeOn:
        if _k_last != 0:
            root_k: uint256 = convert(sqrt(convert(_reserve_x * _reserve_y, decimal)), uint256)
            root_k_last: uint256 = convert(sqrt(convert(_k_last, decimal)), uint256)

            if root_k > root_k_last:
                numerator: uint256 = LidexERC20(lp_token).totalSupply() * (root_k - root_k_last)
                denominator: uint256 = (root_k * 5) + root_k_last
                liquidity: uint256 = numerator / denominator
                if liquidity > 0:
                    LidexERC20(lp_token).mint(feeTo, liquidity)
    elif _k_last != 0:
        self.k_last = 0

    
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
    _reserve_x: uint256 = self._get_reserves()[0]
    _reserve_y: uint256 = self._get_reserves()[1]
    balance_x: uint256 = ERC20(self.token_x).balanceOf(self)
    balance_y: uint256 = ERC20(self.token_y).balanceOf(self)

    amount_x: uint256 = balance_x - _reserve_x
    amount_y: uint256 = balance_y - _reserve_y

    lp_token: address = self.lp_token
    feeOn: bool = self._mintFee(_reserve_x, _reserve_y, lp_token)
    
    _totalSupply: uint256 = LidexERC20(lp_token).totalSupply()
    liquidity: uint256 = 0

    if _totalSupply == 0:
        liquidity = convert(sqrt(convert(amount_x * amount_y, decimal)), uint256) - MINIMUM_LIQUIDITY
        LidexERC20(lp_token).mint(ZERO_ADDRESS, MINIMUM_LIQUIDITY) #permanently lock the first MINIMUM_LIQUIDITY tokens
    else:
        liquidity = min(amount_x * _totalSupply / _reserve_x, amount_y * _totalSupply / _reserve_y)

    assert liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED"
    LidexERC20(lp_token).mint(to, liquidity)

    self._update(balance_x, balance_y, _reserve_x, _reserve_y)

    log Mint(msg.sender, amount_x, amount_y)

    return liquidity


@external
@nonreentrant('lock')
def place_long_term_order(_amount_x_in: uint256, _amount_y_in: uint256, to: address, block_number: int128) -> bool:
    """
    @notice
    @dev
    @param
    @param
    @param
    @param
    """
    assert block_number >= block.number and (to != token_x and to != token_y) 
    assert (block_number - block.number) >= 250 and (_amount_x_in !=0 or _amount_y_in != 0)
    #TODO sync() # virtual
    if _amount_x_in > 0 and _amount_y_in == 0:
        #dev long term order should be unique for this expiration block
        assert self.nestedMapX[block_number][msg.sender].amount_x_in == 0
        _amount_x_per_block: uint256 = _amount_x_in / (block_number - block.number)
        self.nestedMapX[block_number][msg.sender] = LongTermOrderX({
            start: block.number,
            x_start = self.reserve_x,
            y_start = self.reserve_y,
            amount_x_in =  _amount_x_in,
            amount_x_per_block = _amount_x_per_block
        })
        if perBlockX[]
        insert(perBlockX, block_number, _amount_x_per_block) #TODO double linked sorted list (insert function) sort and set 2 links

        log NewLongTermOrderX(block.number, self.reserve_x, self.reserve_y, _amount_x_in, _amount_x_per_block) 

    elif _amount_y_in > 0 and _amount_x_in == 0:
        # dev long term order should be unique per each expiration block
        assert self.nestedMapY[block_number][msg.sender].amount_y_in == 0
        _amount_y_per_block: uint256 = _amount_y_in / (block_number - block.number)
        self.nestedMapY[block_number][msg.sender] = LongTermOrderY({
            start: block_number,
            x_start = self.reserve_x,
            y_start = self.reserve_y,
            amount_y_in =_amount_y_in,
            amount_y_per_block = _amount_y_per_block
        })

        insert(perBlockY, block_number, _amount_y_per_block)    #TODO insert function

        log NewLongTermOrderY(block.number, self.reserve_x, self.reserve_y, _amount_y_in, _amount_y_per_block)

    return True

@external
@nonreentrant('lock')
def cancel_long_term_order(exp_block: uint256, is_x: bool) -> bool:
    """
    @notice Cancel long term order and transfer token_x and token_y 
    @dev    
    @param  exp_block Long term order expiration block
    """
    assert exp_block < block.number # long term order must be active
    if is_x: 
        #dev if msg sender has any orders in a system he will be able to cancel only that order
    value_x: uint256 = #?
    value_y: uint256 = #?


    _safe_transfer(token_x, msg.sender, value_x)
    _safe_transfer(token_y, msg.sender, value_y)

@external
@nonreentrant('lock')
def claim(exp_block: uint256) -> bool:
    """
    @notice
    @dev
    @param
    """
    assert exp_block > block.number # long term order must be expired

    if is_x:
        assert nestedMapX[exp_block][msg.sender].amount_x_in != 0
        start: uint256 = self.nestedMapX[exp_block][msg.sender].start
        x_in: uint256 = total_in(start, exp_block, msg.sender)[0]
        y_in: uint256 = total_in(start)[1]
        x_start: uint256 = self.nestedMapX[exp_block][msg.sender].x_start
        y_start: uint256 = self.nestedMapX[exp_block][msg.sender].y_start

        x_end: uint256 = sqrt(convert(self.k_last * x_in / y_in), decimal)) *
        y_end: uint256 = x_start * y_start / x_end
        y_out: uint256 = y_start + y_in - y_end
        _safe_transfer(self.token_y, msg.sender, y_out)
        
        #log Claim()
    else:
        assert nestedMapX[exp_block][msg.sender].amount_x_in != 0
        start: uint256 = self.nestedMapY[exp_block][msg.sender].start
        x_in: uint256 = total_in(start)[0]
        y_in: uint256 = total_in(start)[1]
        x_start: uint256 = self.nestedMapY[exp_block][msg.sender].x_start
        y_start: uint256 = self.nestedMapY[exp_block][msg.sender].y_start

        x_end: uint256 = sqrt(///)
        x_out: uint256 = x_start + x_in - x_end
        _safe_transfer(self.token_x, msg.sender, x_out)

        #log Claim()

    return True

def burn()


def swap()

@internal
def _sync() -> uint256[3]:
    """
    @notice Function to synchronize token reserves with account to total x and y inflow since last_synced_block
    @dev
    """

    return [
        last_synced_block,
        last_synced_index,
        block.numer
    ]

@view
@external
def sync() -> uint256[3]:
    """
    @notice Function to virtually(without state modifications) synchronize reserves and get the current price of token_x and token_y
    @return reserve_x, reserve_y, current block number
    """


def skim()

@internal
def total_in(_start: uint256, _end: uint256, sender: address, is_x: bool) -> uint256[2]:
    """
    @notice Calculate total inflow
    @dev Function uses to calculate account payoff (x_out)
    @return total x inflow and total y inflow
    """
    if is_x:
        x_in: uint256 = 0
        # get the _start block index
        _index: uint256 = self.perBlockX
        for i in (_end - start):



#<--- double linked sorted list --->
@internal
def insert(exp_block: uint256, _amount_per_block: uint256, is_x: bool) -> bool:
    """
    @notice Function to insert a new node in a sorted doubly linked list
    @param
    @param
    @param
    @return 
    """
    if is_x:
        if self.head == 0:
            # if the list is empty
            self.perBlockX[head] = DoubleLinkedList({
                expiration_block: exp_block,
                per_block: _amount_per_block,
                prev_block: 0,
                next_block: 0
            })
        elif exp_block <= self.perBlockX[head].expiration_block:
            # if the node is to be inserted at the beginning of the list
            index

    expiration_block: uint256
    per_block: uint256
    prev_block: uint256
    next_block: uint256
insert(perBlockY, block_number, _amount_y_per_block) 

def remove()

next 