// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./IProposal.sol";
import "./SharedStructs.sol";

contract Proposals is ExecutableProposal{
    
    mapping(bytes32 => SharedStructs.ProposalStruct) _proposals;    //Propuestas registradas por su id
    bytes32[]  _arrayProposals;                                     //Array con las propuestas
    bytes32[]  _acceptedProposals;                                  //Array con las propuestas aprobadas
    bytes32[]  _pendingProposals;                                   //Array con las propuestas pendientes
    bytes32[]  _signalingProposals;                                 //Array con las propuestas
    bytes32[]  _auxProposals;                                       //Array auxiliar para operar
    
    constructor(){}
    
    event LogProposal(string, bytes32);
    
    function executeProposal(bytes32 proposalId) override external payable{
        emit LogProposal("Enhorabuena!Propuesta ejecutada ", proposalId);
    }
    
    function addProposal(bytes32 uidProposal, SharedStructs.ProposalStruct memory proposal) external {
         _proposals[uidProposal] = proposal;
         _arrayProposals.push(uidProposal);
         _pendingProposals.push(uidProposal);
        if(proposal.proposalInfo.budget == 0)
            _signalingProposals.push(uidProposal);

    }
    
    function getProposal(bytes32 uidProposal) external view returns(SharedStructs.ProposalStruct memory){
        return _proposals[uidProposal];
    }
    
    function setProposal(bytes32 uidProposal, SharedStructs.ProposalStruct memory proposal) external {
        _proposals[uidProposal] = proposal;
    }
    
    function getArrayProposals() external view returns(bytes32[] memory){
        return _arrayProposals;
    }
    
    function getAcceptedProposals() external view returns(bytes32[] memory){
        return _acceptedProposals;
    }
    
    function getPendingProposals() external view returns(bytes32[] memory){
        return _pendingProposals;
    }
    
    function getSignalingProposals() external view returns(bytes32[] memory){
        return _signalingProposals;
    }
    
    function addAcceptedProposal(bytes32 uid) external{
        _acceptedProposals.push(uid);
        //Eliminar de la lista pendientes
        _deleteElement(_pendingProposals, uid);
        _pendingProposals = _auxProposals;
        delete _auxProposals;
    }
    
    function deleteFromProposals(bytes32 uid) external {
        SharedStructs.ProposalStruct memory proposal = _proposals[uid];
        if(proposal.accepted){
            //Eliminar de lista de aprobadas
            _deleteElement(_acceptedProposals,uid);
            _acceptedProposals = _auxProposals;
            delete _auxProposals;
        }else{
            //Eliminar de la lista pendientes
            _deleteElement(_pendingProposals, uid);
            _pendingProposals = _auxProposals;
            delete _auxProposals;
        }
        if(proposal.proposalInfo.budget == 0){
            //Eliminar de la lista de propuestas tipo Signaling
            _deleteElement(_signalingProposals, uid);
            _signalingProposals = _auxProposals;
            delete _auxProposals;
        }
        
        //Eliminar del array de propuestas totales
        _deleteElement(_arrayProposals, uid);
        _arrayProposals = _auxProposals;
        delete _auxProposals;
        
        //Eliminar del mapping la propuestas(definir a nulo/vacio)
        SharedStructs.ProposalInfo memory info = SharedStructs.ProposalInfo("","",0);
        _proposals[uid] = SharedStructs.ProposalStruct(info,0,false, address(0x0),address(0x0));
    }
    
    
    function _deleteElement(bytes32[] memory array, bytes32 uid) internal {
        for(uint i = 0; i < array.length; i++){
            bytes32 index = array[i];
            if(index != uid && index != bytes32(0x0)){
                _auxProposals.push(index);
            }
        }
    }
    
}




