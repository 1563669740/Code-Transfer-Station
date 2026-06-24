from src.md5_algo import md5
from src.sha1_algo import sha1


def main():
    plaintext = "123456"
    md5_result = md5(plaintext)
    sha1_result = sha1(plaintext)
    print(f"MD5('{plaintext}') = {md5_result}")
    print(f"SHA1('{plaintext}') = {sha1_result}")


if __name__ == "__main__":
    main()
