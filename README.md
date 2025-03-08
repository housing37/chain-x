# Chain-Exchange (chainX)
initial mvp for chain-exchange integration (ie. buy any pulsechain erc20 directly on ethereume w/o legacy bridging)

## requirements
	- deploy & trade new wpHEX on uniswap (ethereum)
	- maintain 1:1 parity of wpHEX on ethereum to HEX on pulsechain
	- 1:1 parity arb should be instant exchange based from ethereuem to ethereuem
		respective to hidden pulsechain 30 min pulseX bridge integration

## algorithmic design model
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

## solidity design model
	- 