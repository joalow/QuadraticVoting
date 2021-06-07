// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./IProposal.sol";

contract Proposal is ExecutableProposal{
    
    uint private _budget;
    
    constructor(){}
    
    event LogProposal(string, uint);
    
    function executeProposal(uint proposalId) override external payable{
        emit LogProposal("Enhorabuena!Propuesta ejecutada ", proposalId);
    }
    
    function getBudget() external view returns(uint){
        return _budget;
    }
    
}

