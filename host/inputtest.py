"""Sends Minecraft a forwarded right click (hotbar slot N) like the SB add-on does, and prints what comes back."""
import asyncio, json, sys, time
import websockets

async def main(slot, hold):
    async with websockets.connect("ws://127.0.0.1:25599") as ws:
        print("hello:", await ws.recv())
        await ws.send(json.dumps({"t": "slot", "n": slot}))
        await asyncio.sleep(0.2)
        await ws.send(json.dumps({"t": "key", "k": "use", "down": True}))
        await asyncio.sleep(hold)
        await ws.send(json.dumps({"t": "key", "k": "use", "down": False}))
        end = time.time() + 2.0
        while time.time() < end:
            try:
                m = await asyncio.wait_for(ws.recv(), timeout=end - time.time())
            except asyncio.TimeoutError:
                break
            if '"cam"' not in m:
                print("got:", m[:200])

asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 7, float(sys.argv[2]) if len(sys.argv) > 2 else 0.1))
