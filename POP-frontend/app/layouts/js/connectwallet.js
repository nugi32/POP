import { createWeb3Modal, defaultWagmiConfig } from "https://esm.sh/@web3modal/wagmi";
import { mainnet, polygon, bsc } from "https://esm.sh/wagmi/chains";

// Masukkan projectId kamu
const projectId = "52a9a44c36c9cf0288d553c34e8a662d";

const metadata = {
  name: "My Wallet UI",
  description: "Wallet Connect",
  url: window.location.origin,
  icons: ["https://avatars.githubusercontent.com/u/37784886"]
};

const chains = [mainnet, polygon, bsc];

const wagmiConfig = defaultWagmiConfig({
  projectId,
  chains,
  metadata
});

// Init Web3Modal UI (tombol pasti muncul)
createWeb3Modal({
  wagmiConfig,
  projectId,
  chains
});

// ----------------------------------
// AUTO CONNECT / AUTO RECONNECT
// ----------------------------------
(async () => {
  try {
    // wagmi config punya method connectors, kita coba restore session
    const lastConnectorId = localStorage.getItem("wagmi.lastUsedConnector");

    if (lastConnectorId) {
      const connectors = wagmiConfig.connectors;
      const connector = connectors.find(c => c.id === lastConnectorId);

      if (connector) {
        await connector.connect();
        console.log("Reconnected via:", connector.id);
      }
    }
  } catch (e) {
    console.log("Auto reconnect failed:", e);
  }
})();

/*
52a9a44c36c9cf0288d553c34e8a662d

import { createWeb3Modal, defaultWagmiConfig } from "https://esm.sh/@web3modal/wagmi";
import { mainnet, polygon, bsc } from "https://esm.sh/wagmi/chains";
import { getAccount, disconnect } from "https://esm.sh/wagmi/actions";

// ======================
// 1. CONFIG DASAR
// ======================
const projectId = "52a9a44c36c9cf0288d553c34e8a662d"; // pastikan valid

const metadata = {
  name: "My Wallet UI",
  description: "Wallet Connect",
  url: window.location.origin,
  icons: ["https://avatars.githubusercontent.com/u/37784886"]
};

const chains = [mainnet, polygon, bsc];

const wagmiConfig = defaultWagmiConfig({
  projectId,
  chains,
  metadata,
  enableWalletConnect: true,
  enableInjected: true
});

// ======================
// 2. INIT WEB3MODAL
// ======================
createWeb3Modal({
  wagmiConfig,
  projectId,
  chains
});

console.log("Web3Modal init OK");

// ======================
// 3. RECONNECT FIX
// ======================

// Jika user disconnect manual → jangan auto reconnect
const userLoggedOut = localStorage.getItem("userDisconnected") === "1";

if (!userLoggedOut) {
  wagmiConfig.autoConnect = true;
}

// Force load reconnect handler
setTimeout(async () => {
  try {
    const acc = getAccount(wagmiConfig);
    if (acc.status === "connected") {
      console.log("Reconnected:", acc.address);
    }
  } catch (e) {
    console.log("Reconnect error:", e);
  }
}, 300);
  
// ======================
// 4. DISCONNECT FIX 
// ======================
window.addEventListener("DOMContentLoaded", () => {
  const modalEl = document.querySelector("w3m-button");

  // Tangkap event disconnect dari Web3Modal
  window.addEventListener("w3m:disconnect", async () => {
    console.log("Manual disconnect via UI");
    localStorage.setItem("userDisconnected", "1");
    await disconnect(wagmiConfig, {});
  });

  // Jika user connect lagi → hapus status disconnected
  window.addEventListener("w3m:connect", () => {
    console.log("User connected");
    localStorage.removeItem("userDisconnected");
  });
});*/
