module chain

import cryptography { hash_from_hex }

// checkpoints are always multiples of 100k
const checkpoints = [hash_from_hex('00006e037d7b84104208ecf2a8638d23149d712ea810da604ee2f2cb39bae713'),
					 hash_from_hex('1dccc9cc479ba13d6e4dd31eb89557fa85771b57be66e69072179d8cd714ec80'),
					 hash_from_hex('ece8ebde75ca97a433d2258103abf02a86a2d44fddaa58abf2bf641daf2ab3ef'),
					 hash_from_hex('fc97017d283fc3458c08afd6a052905112ec5b5a8c2600f33d5e9a2141255fb9'),
					 hash_from_hex('141acb0686759a1e3b6d4ca0d8eb090152d3c05449ebaab232eb7af579958c9a'),
					 hash_from_hex('ddb7fce01c8a120cdce38b6649f49f5aa9a3fd57528bdf82102396709f1f2bd7'),
					 hash_from_hex('9ed660a3dcec1eee8c077a808b65d92dd6fd1db2b2ffddf089ee860af11400e6'),
					 hash_from_hex('e60834a8d989954819436c113764886a3f977a6e6da7218c38bef2f8bcfc2ac7'),
					 hash_from_hex('393f7fcf5652b15ef97d578a9d89c145c2565da094e4d88828f91968f79e9e73'),
					 hash_from_hex('76ee2034624ef5ab99b72dcfb1b4d9916496368ac9622842462bf9cbe20f887b'),
					 hash_from_hex('6e1936857fccda6bbb0469ec345f571f3bbc3b631537729459eab82c867a9116'),
					 hash_from_hex('89bae1a8483a7a1471bddb19307315bb7ff7a2c8e1215e5d7b8047dcad450b8d'),
					 hash_from_hex('65b3cc8e3e8df5965cf2f1ea5c1bf993874915c198d2d9a4676a36c466ac7f9a'),
					 hash_from_hex('063c8c3c704f4030c4f527a4949e043470ae9df4021a5996c2c047ce4e8ebf13'),
					 hash_from_hex('052728f056d03e5b88d6826b2044cecea348c15817006155bf34e02449db42af')]
