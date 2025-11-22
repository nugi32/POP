  const connectButton = document.getElementById('connectButton');
  const walletAddressText = document.getElementById('walletAddress');

  connectButton.addEventListener('click', async () => {
    // Periksa apakah MetaMask terpasang
    if (typeof window.ethereum !== 'undefined') {
      try {
        // Meminta akses ke akun
        const accounts = await window.ethereum.request({
          method: 'eth_requestAccounts'
        });

        const account = accounts[0];
        walletAddressText.innerText = "Connected: " + account;

        // Inisialisasi Web3
        const web3 = new Web3(window.ethereum);

        console.log("Web3 ready:", web3);
      } catch (error) {
        console.error("User rejected connection:", error);
      }
    } else {
      alert("MetaMask tidak ditemukan! Silakan install MetaMask.");
    }
  });