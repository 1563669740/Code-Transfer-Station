from src.md5_algo import md5


def main():
    plaintext = "123456"
    result = md5(plaintext)
    print(f"MD5('{plaintext}') = {result}")


if __name__ == "__main__":
    main()
