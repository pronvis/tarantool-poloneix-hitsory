---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by pronvis.
--- DateTime: 15/07/2018 15:54
---

local log = require 'log'
require('libraries.functions')

local M = {}
local app
local http_client
local json
local fiber
local clock

function M.init(config)
    clock = require'clock'
    app = require 'app'
    json = require 'json'
    fiber = require 'fiber'
    M.config = config
    http_client = require('http.client').new({1})
end

local function get_average_price(bids)
    local multiple_function = function(t) return t[1]*t[2] end
    local amount_on_price = map(multiple_function, bids)
    return reduce(operator.add, amount_on_price)
end

function M.bts_to_usdt_avg_price(depth)
    local url = 'https://poloniex.com/public?command=returnOrderBook&currencyPair=USDT_BTC&depth='..depth
    local response = http_client:request('GET', url)
    if response.body then
        local orders = json.decode(response.body)
        local sells = get_average_price(orders.asks)
        local buys = get_average_price(orders.bids)
        local res = {sum = 0, avg_price = 0 }
        local i = 1
        while(res.sum < 20000) do
            local ask = orders.asks[i]
            res.sum = res.sum + ask[1] * ask[2]
            res.avg_price = res.avg_price + ask[1]
            i = i + 1
        end
        res.avg_price = res.avg_price / i

        return sells, buys, res.avg_price
    else
        log.error('fail to get response from poloneix')
    end
end

local function fill_prices_table()
    local sells, buys, avg_price = M.bts_to_usdt_avg_price(100000)
    if sells and buys then
        local now = math.floor(clock.time()*1000)
        box.space.usdt_btc_orders:insert({now, sells, buys, avg_price})
        log.debug('insert to prices; sells='..sells..'; buys='..buys)
    end
end

function M.fill_fiber(channel)
    local running = true
    while running do
        local task = channel:get()
        if task ~= nil then
            fill_prices_table()
        else
            log.error('fill_fiber is stopped!')
            running = false
        end
    end
end

local fiber_channel
local filler_fiber
local awaker_fiber
function M.start()
    fiber_channel = fiber.channel()
    filler_fiber = fiber.create(M.fill_fiber, fiber_channel)
    filler_fiber:name('filler_fiber')

    local function awake_channel(channel)
        while true do
            channel:put('')
            fiber.sleep(1)
        end
    end
    awaker_fiber = fiber.create(awake_channel, fiber_channel)
    awaker_fiber:name('awaker_fiber')
end

function M.destroy()
end

return M
