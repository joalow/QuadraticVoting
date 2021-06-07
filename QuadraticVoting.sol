// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./TokenManager.sol";
import "./Proposal.sol";

contract QuadraticVoting{
    
    address _owner; //Indica el creador/propietario del contrato
    bool _statusOpen; //Indica si la votacion esta en estado abierto/open
    
    uint _maxTokens; //Maximo n tokens a la venta para la votacion
    uint _tokenValue; //Valor del token en wei
    uint _totalBudget; //Presupuesto para financiar propuestas
    
    TokenManager _tokens; //Atributo del contrato que gestiona los tokens
     
     //Informacion relativa a la propuesta
     struct ProposalInfo {
        string title;
        string description;
        uint budget;
     }
     
     //Propuesta
    struct ProposalStruct{
        ProposalInfo proposalInfo;
        uint votos;
        bool accepted;
        address proposal;
        address participant;
    }
    
    mapping(address => mapping(bytes32 => uint)) _votos; //Numero de votos realizados por un participante a una o varias propuestas 
    mapping(address => uint) _participants;              //Participantes registrados y sus saldos en wei 
    mapping(bytes32 => ProposalStruct) _proposals;             //Propuestas registradas por su id
    
    bytes32[]  _arrayProposals;     //Array con las propuestas
    bytes32[] _arrayParticipants;   //Array de participantes   
    
    constructor(uint tokenVal, uint tokens, uint amount){
        _maxTokens = tokens;
        _tokenValue = tokenVal;
        _totalBudget = amount;
        _owner = msg.sender;
        _statusOpen = false;
        _tokens = new TokenManager("QToken","QTK");
    }
    
    function testBalance() public view returns(uint){
        return address(this).balance;
    } 
    function testBalanceTokens() public view returns(uint){
        return _tokens.balanceOf(msg.sender);
    }
    
    function testTotalSupply() public view returns(uint){
        return _tokens.totalSupply();
    }
    
    
    // Realiza la apertura de la votacion
    // Solo la puede ejecutar el propiertario del contrato
    // Se pone a true indicando que la votacion se encuentra abierta la variable _statusOpen definida para ello
    function openVoting() public {
        require(msg.sender == _owner,"La apertura de votacion solo corresponde al creador del contrato");
        _statusOpen = true;
    }
    
    // Inscribe/Añade un participante aun no registrado a la votacion, antes o durante la votacion
    // El participante debe ingresar ether suficiente para comprar 1 token
    // Se hacen estas comprobaciones ademas de comprobar que no se supere numero de tokens maximo establecido
    // y se procede a la obtencion del token/es a trabes del contrato TokenManager
    function addParticipant() public payable {
        //COMPROBACION DE Participante EXISTENTE
        require(_participants[msg.sender] == 0 , "Participante ya esta inscrito" );
        //ETHER TRANSFERIDO SEA AL MENOS EL EQUIVALENTE A 1 TOKEN
        require(msg.value >= _tokenValue, "Participante debe obtener al menos 1 token para participar");
        //OBTENER EL TOKEN 
        uint tokens = msg.value/_tokenValue;
        require(_tokens.totalSupply() + tokens <= _maxTokens,"No se pueden adquirir tantos tokens, sobrepasa los tokens permitidos");
        _participants[msg.sender] = msg.value;
        _tokens.mintImplement(msg.sender,tokens);
    }
    
    // Crea una propuesta por un participante existente
    // Se comprueba que el participante exista, que los valores de los parametros sean permitidos y se registra la propuesta.
    // En este caso se hace un keccak256 del titulo de propuesta y se comprueba que dos propuestas no puedan ser iguales por su titulo.
    function addProposal(string memory titulo, string memory descripcion, uint amount, address contractProposal) public returns(bytes32){
        //Comprobaciones datos
        require(bytes(titulo).length > 0, "Titulo requerido");
        require(bytes(descripcion).length > 0, "Descripcion requerido");
        require(amount >= 0, "Presupuesto >= 0");
        require(contractProposal != address(0x0), "Contrato de la propuesta requerido");
        //Comprobar existencia propuesta
        bytes memory tituloBytes = bytes(titulo);
        bytes32 uid = keccak256(tituloBytes);        
        require(_proposals[uid].proposal == address(0x0),"La propuesta ya existe");
        // Se comprueba que el participante exista
        require(_participants[msg.sender] != 0, "Participante no existe");

        //Añadir propuesta
        ProposalInfo memory proposalInfo = ProposalInfo(titulo,descripcion,amount);
        _proposals[uid] = ProposalStruct(
            {proposalInfo: proposalInfo, votos:0, accepted: false, proposal: contractProposal,
            participant: msg.sender});
        _arrayProposals.push(uid);
        return uid;
    }
    
    function _deleteFromProposals(bytes32 uid) internal {
        uint length = _arrayProposals.length;
        for(uint i = 0; i < length; i ++){
            if(_arrayProposals[i] == uid){
                delete _arrayProposals[i];
                break;
            }
        }
    }
    
    // Cancela una propuesta.
    // Se requiere que el que ejecute la funcion sea el creador de la propuesta, que la propuesta exista y no este ya aprobada.
    // Los tokens recibidos para votar son devueltos a sus propietarios
    function cancelProposal(bytes32 uid) public {
        // El emisor es el creador de la propuesta
        require(_proposals[uid].participant == msg.sender, "El emisor debe ser el creador de la propuesta");
        _cancelProposal(uid);
    }

    
    // Realiza la compra de tokens a un participante.
    // Se requiere que el participante exista y que no se supere el maximo permitido de tokens establecido.
    function buyTokens() public payable{
        uint tokens = msg.value/_tokenValue;
        require(_tokens.totalSupply() + tokens <= _maxTokens,"No se pueden adquirir tantos tokens, sobrepasa los tokens permitidos");
        _participants[msg.sender] += msg.value; //SAFEMATH!!!!!!!!!!!!!!!!!!!!!!!!!
        _tokens.mintImplement(msg.sender,tokens);
    }
    
    // Permite a un participante devolver los tokens no gastados en votaciones y recuperar el dinero invertido en ellos.
    // Se requiere que el participante exista y que tenga al menos 1 token.
    function sellTokens() public {
        require(_participants[msg.sender] != 0, "Participante no existe");
        uint tokens = _tokens.balanceOf(msg.sender);
        require(tokens > 0 , "No hay tokens para devolver.");
        uint amountToTransfer = tokens * _tokenValue ; //SAFEMATHH!!!!!!!!!!!!!!!!!!!!
        //Se resta el saldo del participante, se destruyen los tokens y se transfiere los Wei al participante
        _participants[msg.sender] -= amountToTransfer;
        _tokens.burnImplement(msg.sender,tokens);
        payable(msg.sender).transfer(amountToTransfer);
    }
    
    // Devuelve el contrato ERC20.
    // Se requiere que el participante exista.
    function getERC20Voting() public view returns(address){
        return address(_tokens);
    }
    
    // Devuelve un array con los identificadores de todas las propuestas pendientes de arpobar.
    function getPendingProposals() public pure returns(bytes32[] memory){
        bytes32[] memory array;
        // uint length = _arrayProposals.length;
        // for(uint i = 0; i < length; i ++){
        //     bytes32 uid = _arrayProposals[i];
        //     if(!_proposals[uid].accepted){
        //         array.push(uid);
        //     }
        // }
        return array;
    }
    
    // Devuelve un array con los identificadores de todas las propuestas ya aprobadas.
    function getApprovedProposals() public pure returns(bytes32[] memory){
        bytes32[] memory array;
        return array;
    }
    
    // Devuelve un array con los identificadores de todas las propuestas de tipo signaling.
    function getSinalingProposals() public pure returns(bytes32[] memory){
        bytes32[] memory array;
        return array;
    }
    
    // Devuelve los datos asociados a una propuesta dado su identificador.
    // Se requiere que el identificador dado exista como propuesta.
    function getProposalInfo(bytes32 uid) public view returns(ProposalInfo memory){
        ProposalStruct memory proposal = _proposals[uid];
        require( proposal.proposal != address(0x0),"Propuesta no existe");
        return proposal.proposalInfo;
    }
    
    // Realiza el voto del participante que invoca esta función.
    // Se calcula los tokens necesarios para depositar los votos que se van a depositar,
    // Se comprueba que el participante posee los suficientes tokens para comprar los votos 
    // y que ha cedido (con approve) el uso de esos tokens a la cuenta del contrato de la votación.
    // Se transfiere la cantidad de tokens correspondiente desde la cuenta del participante a la cuenta de este contrato para poder operar con ellos.
    function stake(bytes32 uidProposal , uint nVotos) public {
        // Se calcula los tokens necesarios para este numero de votos teniendo en cuenta
        // las posibles anteriores votaciones realizadas a la misma propuesta
        uint votosDone = _votos[msg.sender][uidProposal];
        nVotos += votosDone;
        uint nTokensGastados = votosDone*votosDone;
        uint nTokensNuevos = (nVotos*nVotos) - nTokensGastados;
        require(_tokens.allowance(msg.sender,address(this)) >= nTokensNuevos, "Numero de tokens insuficiente para realizar la votacion");
        _votos[msg.sender][uidProposal] = nVotos;
        _tokens.transferFrom(msg.sender, _proposals[uidProposal].proposal, nTokensNuevos);
    }
    
    // Emisor deposita la máxima cantidad de votos posible en la propuesta que se recibe como parámetro.
    // Se comprueba que ha cedido (con approve) el uso de esos tokens a la cuenta del contrato de la votación.
    function stakeAllToProposal(bytes32 uidProposal) public {
        // Se calcula los tokens posibles con los tokens propios actuales y teniendo en cuenta
        // las posibles anteriores votaciones realizadas a la misma propuesta
        uint votosDone = _votos[msg.sender][uidProposal];
        uint sumTokens = (votosDone*votosDone) + _tokens.balanceOf(msg.sender);
        uint votosPosibles = _sqrt(sumTokens);
        uint tokensPosibles = (votosPosibles*votosPosibles)-(votosDone*votosDone);
        _votos[msg.sender][uidProposal] = votosPosibles;
        _tokens.transferFrom(msg.sender, _proposals[uidProposal].proposal, tokensPosibles);
    }
    
    // Elimina (si es posble)la cantidad indicada de votos depositados por el participante que invoca esta función
    // de la propuesta recibida y devolver los tokens utilizados.
    // El participante solo puede retirar de una propuesta votos que él haya depositado anteriormente.
    function withdrawFromProposal(bytes32 uidProposal , uint nVotos) public {
        require(_participants[msg.sender] != 0,"No existe participante");
        uint votosDone = _votos[msg.sender][uidProposal];
        require( votosDone > 0, "No hay votos que retirar de este participante en esta propuesta");
        require( votosDone - nVotos >= 0, "No se pueden retirar mas votos de los realizados");
        uint actualVotos = votosDone - nVotos;
        uint actualTokens = (votosDone*votosDone) - (actualVotos*actualVotos);
        _votos[msg.sender][uidProposal] = actualVotos;
        _tokens.transferFrom( _proposals[uidProposal].proposal, msg.sender, actualTokens);
    }
    
    // Elimina todos los votos depositados por el participante que invoca esta función de la propuesta indicada y devolver los tokens utilizados.
    // El participante solo puede retirar de una propuesta votos que él haya depositado anteriormente
    function withdrawAllFromProposal(bytes32 uidProposal) public {
        require(_participants[msg.sender] != 0,"No existe participante");
        uint votosDone = _votos[msg.sender][uidProposal];
        require( votosDone > 0, "No hay votos que retirar de este participante en esta propuesta");
         _votos[msg.sender][uidProposal] = 0;
        _tokens.transferFrom( _proposals[uidProposal].proposal, msg.sender, (votosDone*votosDone) );
    }
    
    // Comprueba si se cumplen las condiciones para ejecutar la propuesta y la ejecuta
    // Se comprueba que el presupuesto del contrato sea > 0, el requerimiento (1)(el presupuesto del contrato de votación más el importe recaudado 
    // por los votos recibidos es suficiente para financiar la propuesta) y el requerimiento (2)(el número de votos recibidos supera el umbral definido)
    // Se transfiere al contrato el dinero presupuestado para su ejecucion y se actualiza el presupuesto disponible para otras propuestas.
    // Se eliminan/consumen los tokens asociados a los votos recibidos por la propuesta
    function _executeProposal(bytes32 uidProposal) internal {
        if(_isExecutable(uidProposal)){ //Se comprueban las condiciones para ejecutar la propuesta
            ProposalStruct memory proposal = _proposals[uidProposal];
            uint presupuestoObtenido = (proposal.votos * _tokenValue);
            uint diferenciaPresupuestoObtenido = proposal.proposalInfo.budget - presupuestoObtenido;
            if(diferenciaPresupuestoObtenido > 0){ //Si el presupuesto obtenido no llega al presupuesto de la propuesta se resta lo que falta al presupuesto total
                _totalBudget -= diferenciaPresupuestoObtenido;
            }
            //Se eliminan todos los tokens obtenidos de la propuesta y se actualiza el estado de la propuesta
            _tokens.burnImplement(proposal.proposal, _tokens.balanceOf(proposal.proposal));
            proposal.accepted = true;
            //Se transfiere el saldo presupuestado a la propuesta
            payable(proposal.proposal).transfer(proposal.proposalInfo.budget);
            //Se ejecuta la propuesta
            //Proposal(proposal.proposal)._executeProposal(uidProposal);            
        }
    }
    
    // Cierre del periodo de votación
    // Se requiere que sea el usuario creador de este contrato quien ejecute esta funcion
    // - Las propuestas no aprobadas son descartadas y el saldo de tokens en Wei recibidos por esas propuestas son devueltos a sus usuarios
    // - Las propuestas signaling son ejecutadas y el saldo de tokens en Wei recibidos por esas propuestas son devueltos a sus usuarios
    // - El presupuesto de la votacion no gastado es devuelto al usuario creador del contrato
    // - Los tokens no utilizados para votar son eliminados y el saldo en Wei es devuelto a sus propietarios
    function closeVoting() public {
        assert(msg.sender == _owner); //El emisor debe ser el creador del contrato
        bytes32[] memory pendingProposals;// !!!!!!
        uint lengthArray = pendingProposals.length;
        for(uint i = 0; i < lengthArray; i++){
            _cancelProposal(pendingProposals[i]);
        }
        bytes32[] memory signalingProposals;// !!!!!!
        lengthArray = signalingProposals.length;
         for(uint i = 0; i < lengthArray; i++){
            //Proposal(proposal.proposal)._executeProposal(uidProposal); //Se ejecutan propuestas
            _giveBackTokens(signalingProposals[i]); //Se devuelven los tokens a participantes
        }
        //Se eliminan los tokens pendientes de los usuarios y se les devuelve sus respectivos saldos
        
        //Se devuelve el presupuesto restante del contrato al owner
        
        //Se cierra la votacion
        _statusOpen = false;
    }
    
    //Funcion interna que calcula la raiz cuadrada 
    function _sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    //Funcion interna que calcula el umbral con fixedpoints
    function _getUmbral(bytes32 uidProposal) internal view returns(uint256){
        ufixed256x18 totalBudget = ufixed256x18(_totalBudget);
        ufixed256x18 proposalBudget = ufixed256x18(_proposals[uidProposal].proposalInfo.budget);
        ufixed256x18 k = 0.2;
        ufixed256x18 umbral = ( k + (proposalBudget/totalBudget)* ufixed256x18(_arrayParticipants.length) + ufixed256x18(_arrayProposals.length));
        uint256 ret = uint256(umbral>>18);
        return ret;
    }


    //Funcion interna que calcula si la propuesta se puede ejecutar/aceptar
    function _isExecutable(bytes32 uidProposal) internal view returns(bool){
        if(_totalBudget > 0 ){ // Comprueba si queda presupuesto del contrato para financiar propuestas
            ProposalStruct memory proposal = _proposals[uidProposal];
            if(_totalBudget + (proposal.votos * _tokenValue) > proposal.proposalInfo.budget){ // Se comprueba el requerimiento (1) Se ssupera el presupuesto de la propuesta
                uint umbral = _getUmbral(uidProposal);
                if(proposal.votos > umbral) // Se comprueba si se supera el requerimiento(2), el umbral de votos de la propuesta
                    return true;
            }
        }
        return false;
    }
    
        
    function _giveBackTokens(bytes32 uid) internal {
        
    }
    
    //Funcion interna que se encarga de cancelar una propuesta existente no aprobada y devolver los tokens a sus propietarios
    function _cancelProposal(bytes32 uid) internal {
        ProposalStruct memory proposal = _proposals[uid];
        // Exista la propuesta
        require(proposal.proposal != address(0x0),"La propuesta no existe");
        // No este aprobada
        require(proposal.accepted == false, "La propesta est aprobada");
        
        //Se devuelven los tokens a sus propietarios
        _giveBackTokens(uid);
        //Se elimina la propuesta
        _deleteFromProposals(uid);
    }
}

