from web3.datastructures import AttributeDict
from hexbytes import HexBytes

FACTORY_SRC = {
    'abi': './abis/factory.json',
    'address': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    'events': [
        'PoolCreated(indexed address,indexed address,indexed uint24,int24,address)'],
    'is_factory': True,
    'name': 'Factory',
    'startBlock': 12369621
}

DATA_SOURCES = [
    FACTORY_SRC,
    {
        'abi': './abis/NonfungiblePositionManager.json',
        'address': '0xC36442b4a4522E871399CD717aBDD847Ab11FE88',
        'events': [
            'IncreaseLiquidity(indexed uint256,uint128,uint256,uint256)',
            'DecreaseLiquidity(indexed uint256,uint128,uint256,uint256)',
            'Collect(indexed uint256,address,uint256,uint256)',
            'Transfer(indexed address,indexed address,indexed uint256)'
        ],
       'is_factory': False,
       'name': 'NonfungiblePositionManager',
       'startBlock': 12369651
    }
]

FACTORY_EVENTS = [
    AttributeDict({
        'args': AttributeDict({
            'token0': '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984',
            'token1': '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
            'fee': 3000,
            'tickSpacing': 60,
            'pool': '0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801'
        }),
        'event': 'PoolCreated',
        'logIndex': 24,
        'transactionIndex': 33,
        'transactionHash':
            HexBytes('0x37d8f4b1b371fde9e4b1942588d16a1cbf424b7c66e731ec915aca785ca2efcf'),
        'address': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
        'blockHash':
            HexBytes('0xe8228e3e736a42c7357d2ce6882a1662c588ce608897dd53c3053bcbefb4309a'),
        'blockNumber': 12369739
    }),
    AttributeDict({
        'args': AttributeDict({
            'token0': '0x6B175474E89094C44Da98b954EedeAC495271d0F',
            'token1': '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
            'fee': 500,
            'tickSpacing': 10,
            'pool': '0x6c6Bc977E13Df9b0de53b251522280BB72383700'
        }),
        'event': 'PoolCreated',
        'logIndex': 80,
        'transactionIndex': 82,
        'transactionHash':
            HexBytes('0xa877e18bbdcf69b751f56b4aa5b91a903ae69de2d775f1eb27fba4ba25abff2a'),
        'address': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
        'blockHash':
            HexBytes('0xd4325ee72c39999e778a9908f5fb0803f78e30c441a5f2ce5c65eee0e0eba59d'),
        'blockNumber': 12369760
    })
]

processed_FACTORY_EVENTS = [{
    'address': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    'args': '{"token0": "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984", "token1": '
        '"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "fee": 3000, '
        '"tickSpacing": 60, "pool": '
        '"0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801"}',
    'blockHash':
        HexBytes('0xe8228e3e736a42c7357d2ce6882a1662c588ce608897dd53c3053bcbefb4309a'),
    'blockNumber': 12369739,
    'event': 'PoolCreated',
    'logIndex': 24,
    'transactionHash':
        HexBytes('0x37d8f4b1b371fde9e4b1942588d16a1cbf424b7c66e731ec915aca785ca2efcf'),
    'transactionIndex': 33
}, {
    'address': '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    'args': '{"token0": "0x6B175474E89094C44Da98b954EedeAC495271d0F", "token1": '
        '"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "fee": 500, '
        '"tickSpacing": 10, "pool": '
        '"0x6c6Bc977E13Df9b0de53b251522280BB72383700"}',
    'blockHash':
        HexBytes('0xd4325ee72c39999e778a9908f5fb0803f78e30c441a5f2ce5c65eee0e0eba59d'),
    'blockNumber': 12369760,
    'event': 'PoolCreated',
    'logIndex': 80,
    'transactionHash':
        HexBytes('0xa877e18bbdcf69b751f56b4aa5b91a903ae69de2d775f1eb27fba4ba25abff2a'),
    'transactionIndex': 82
}]

POOL_EVENTS = [
    'Initialize(uint160,int24)',
    'Swap(indexed address,indexed address,int256,int256,uint160,uint128,int24)',
    'Mint(address,indexed address,indexed int24,indexed int24,uint128,uint256,uint256)',
    'Burn(indexed address,indexed int24,indexed int24,uint128,uint256,uint256)',
    'Flash(indexed address,indexed address,uint256,uint256,uint256,uint256)'
]

rendered_TEMPLATES = [{
    'abi': './abis/pool.json',
    'address': '0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801',
    'events': POOL_EVENTS,
    'name': 'Pool',
    'startBlock': 12369739
}, {
    'abi': './abis/pool.json',
    'address': '0x6c6Bc977E13Df9b0de53b251522280BB72383700',
    'events': POOL_EVENTS,
    'name': 'Pool',
    'startBlock': 12369760
}]

