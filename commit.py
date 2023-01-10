from hexbytes import HexBytes
from web3 import Web3
import secrets


def get_commit(data: int, key: HexBytes) -> HexBytes:
    return HexBytes(Web3.solidityKeccak(['int256', 'bytes32'], [data, key]))


print("Selecting a random key.")
key = HexBytes(secrets.token_bytes(32))
print(f"The key is: {key.hex()}")


num = int(input("Enter an int: "))
print("The commitment to the int you entered is: ", get_commit(num, key).hex())
