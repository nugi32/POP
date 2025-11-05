"use client";

import { useState } from 'react';
import { Button } from '@/components/Button';
import { Card } from '@/components/Card';
import { Navbar } from '@/components/Navbar';

export default function AdminDashboard() {
  const [employees, setEmployees] = useState([]);
  const [systemStats, setSystemStats] = useState({
    totalUsers: 0,
    totalTasks: 0,
    systemBalance: '0'
  });
  const [adminAddress, setAdminAddress] = useState('');
  const [loading, setLoading] = useState(false);

  const connectWallet = async () => {
    try {
      if (typeof window.ethereum !== 'undefined') {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        setAdminAddress(accounts[0]);
      }
    } catch (error) {
      console.error('Error connecting wallet:', error);
    }
  };

  return (
    <div>
      <Navbar userType="admin" address={adminAddress || '0x0'} />
      
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {!adminAddress ? (
          <div className="text-center">
            <Button onClick={connectWallet}>Connect Wallet</Button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <Card title="Employee Management">
              {loading ? (
                <div className="text-center py-4">Loading...</div>
              ) : employees.length === 0 ? (
                <div className="text-center py-4 text-gray-500">No employees found</div>
              ) : (
                <div>Employee list will go here</div>
              )}
              <div className="mt-4">
                <Button variant="primary">Add New Employee</Button>
              </div>
            </Card>

            <Card title="System Overview">
              <div className="space-y-4">
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Total Users:</span>
                  <span className="font-semibold">{systemStats.totalUsers}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">Total Tasks:</span>
                  <span className="font-semibold">{systemStats.totalTasks}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-600">System Balance:</span>
                  <span className="font-semibold">{systemStats.systemBalance} ETH</span>
                </div>
                <div className="mt-4">
                  <Button variant="secondary" className="w-full">Update System Parameters</Button>
                </div>
              </div>
            </Card>
          </div>
        )}
      </div>
    </div>
  );
}