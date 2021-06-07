// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

library SharedStructs{
    
    //Informacion relativa a la propuesta
     struct ProposalInfo {
        string title;
        string description;
        uint budget;
     }
     
    //Propuesta
    struct ProposalStruct{
        ProposalInfo proposalInfo;
        uint totalVotos;
        bool accepted;
        address proposal;
        address participant;
    }
    
}

