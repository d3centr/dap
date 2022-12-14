#!/usr/bin/env python

from prepost_block_tracer import anon_event_shield

from hexbytes import HexBytes
from web3.datastructures import AttributeDict

TOPIC = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'

def anon_event_test(topic):
    assert(anon_event_shield(AttributeDict({'topics': []})) == '')
    assert(anon_event_shield(AttributeDict({'topics': [topic]})) == TOPIC)

if __name__ == '__main__':
    print('anon_event_test()')
    anon_event_test(HexBytes(TOPIC))
    print('ok')
    print('test suite passed')

