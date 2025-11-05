"use client";

import { useState } from 'react';
import { Button } from '@/components/Button';
import { Card } from '@/components/Card';
import { Navbar } from '@/components/Navbar';

export default function UserDashboard() {
  const [tasks, setTasks] = useState([]);
  const [reputation, setReputation] = useState(0);
  const [loading, setLoading] = useState(false);
  const [userAddress, setUserAddress] = useState('');

  // Function to connect wallet
  const connectWallet = async () => {
    try {
      if (typeof window.ethereum !== 'undefined') {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        setUserAddress(accounts[0]);
      }
    } catch (error) {
      console.error('Error connecting wallet:', error);
    }
  };

  return (
    <div>
      <Navbar userType="user" address={userAddress || '0x0'} />
      
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {!userAddress ? (
          <div className="text-center">
            <Button onClick={connectWallet}>Connect Wallet</Button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <Card title="My Tasks">
              {loading ? (
                <div className="text-center py-4">Loading...</div>
              ) : tasks.length === 0 ? (
                <div className="text-center py-4 text-gray-500">No tasks found</div>
              ) : (
                <div>Task list will go here</div>
              )}
            </Card>

            <Card title="My Reputation">
              <div className="text-center py-4">
                <div className="text-4xl font-bold text-blue-600">{reputation}</div>
                <div className="text-gray-500 mt-2">Reputation Points</div>
              </div>
            </Card>
          </div>
        )}
      </div>
    </div>
  );
}