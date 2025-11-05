import userRegisterAbi from '../../../artifacts/contracts/User/register.sol/UserRegister.json';
import reputationAbi from '../../../artifacts/contracts/Logic/Reputation.sol/UserReputation.json';
import employeeAssignmentAbi from '../../../artifacts/contracts/Owner/employe_assignment.sol/EmployeeAssignment.json';
import systemWalletAbi from '../../../artifacts/contracts/system/Wallet.sol/System_wallet.json';

// These addresses will need to be updated after deployment
export const CONTRACT_ADDRESSES = {
  USER_REGISTER: '',
  REPUTATION: '',
  EMPLOYEE_ASSIGNMENT: '',
  SYSTEM_WALLET: ''
};

export const CONTRACT_ABIS = {
  USER_REGISTER: userRegisterAbi.abi,
  REPUTATION: reputationAbi.abi,
  EMPLOYEE_ASSIGNMENT: employeeAssignmentAbi.abi,
  SYSTEM_WALLET: systemWalletAbi.abi
};