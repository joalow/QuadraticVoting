// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./TokenManager.sol";
import "./Proposals.sol";
import "./SharedStructs.sol";
import "./utils/SafeMath.sol";

contract QuadraticVoting{
    
    address _owner; //Indica el creador/propietario del contrato
    bool _statusOpen; //Indica si la votacion esta en estado abierto/open
    
    uint _maxTokens; //Maximo n tokens a la venta para la votacion
    uint _tokenValue; //Valor del token en wei
    uint _totalBudget; //Presupuesto para financiar propuestas
    
    TokenManager _tokens; //Contrato que gestiona los tokens
    Proposals _proposals; //Contrato que gestiona las proposals
    
        
    mapping(address => mapping(bytes32 => uint)) _votos; //Numero de votos realizados por un participante a una o varias propuestas 
    mapping(address => uint) _participants;              //Participantes registrados y sus saldos en wei 
    address[] _arrayParticipants;                        //Array de participantes   
    
    constructor(uint tokenVal, uint tokens) payable {
        _maxTokens = tokens;
        _tokenValue = tokenVal;
        _totalBudget = msg.value;
        _owner = msg.sender;
        _statusOpen = false;
        _tokens = new TokenManager("QToken","QTK");
        _proposals = new Proposals();
    }
    
    /** MODIFIERS */
    
    modifier OwnerContract(){
        assert(msg.sender == _owner);_;
    }
    
    modifier ExistsParticipant(){
        // Se comprueba que el participante exista
        require(_participants[msg.sender] != 0, "Participante no existe");_;
    }
    
    modifier VotingOpened(){
        require(_statusOpen == true, "La votacion no se encuentra abierta");_;
    }
    
    modifier PendingProposal(bytes32 uidProposal){
        require(_proposals.getProposal(uidProposal).accepted == false, "La propuesta ya esta aceptada");
        require(_proposals.getProposal(uidProposal).proposalInfo.budget != 0, "La propuesta es de tipo signaling");_;
    }
    
    
    // Realiza la apertura de la votacion
    // Solo la puede ejecutar el propiertario del contrato
    // Se pone a true indicando que la votacion se encuentra abierta la variable _statusOpen definida para ello
    function openVoting() public OwnerContract {
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
        require(SafeMath.add(_tokens.totalSupply() , tokens) <= _maxTokens,"No se pueden adquirir tantos tokens, sobrepasa los tokens permitidos");
        _participants[msg.sender] = msg.value;
        _arrayParticipants.push(msg.sender);
        _tokens.mintImplement(msg.sender,tokens);
        if(_statusOpen){
            //Check if any proposal is Executable
            _checkExecutes();        
        }
        
    }
    
    // Crea una propuesta por un participante existente
    // Se comprueba que el participante exista, que los valores de los parametros sean permitidos y se registra la propuesta.
    // En este caso se hace un keccak256 del titulo de propuesta y se comprueba que dos propuestas no puedan ser iguales por su titulo.
    function addProposal(string memory titulo, string memory descripcion, uint amount, address contractProposal) public ExistsParticipant returns(bytes32){
        //Comprobaciones datos
        require(bytes(titulo).length > 0, "Titulo requerido");
        require(bytes(descripcion).length > 0, "Descripcion requerido");
        require(amount >= 0, "Presupuesto >= 0");
        require(contractProposal != address(0x0), "Contrato de la propuesta requerido");
        //Comprobar existencia propuesta
        bytes memory tituloBytes = bytes(titulo);
        bytes32 uid = keccak256(tituloBytes);        
        require(_proposals.getProposal(uid).proposal == address(0x0),"La propuesta ya existe");

        //Añadir propuesta
        SharedStructs.ProposalInfo memory proposalInfo = SharedStructs.ProposalInfo(titulo,descripcion,amount);
        SharedStructs.ProposalStruct memory proposal = SharedStructs.ProposalStruct(
            {proposalInfo: proposalInfo, totalVotos:0, accepted: false, proposal: contractProposal,
            participant: msg.sender});
        
        _proposals.addProposal(uid,proposal);
        if(_statusOpen){
            //Check if any proposal is Executable
            _checkExecutes();        
        }
        
        return uid;
    }
    
    
    // Cancela una propuesta.
    // Se requiere que el que ejecute la funcion sea el creador de la propuesta, que la propuesta exista y no este ya aprobada.
    // Los tokens recibidos para votar son devueltos a sus propietarios
    function cancelProposal(bytes32 uid) public {
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uid);
        require(proposal.participant == msg.sender, "El emisor debe ser el creador de la propuesta y la propuesta existir");
        // Exista la propuesta
        require(proposal.proposal != address(0x0),"La propuesta no existe");
        // No este aprobada
        require(proposal.accepted == false, "La propesta fue ya aprobada");
        
        //Se devuelven los tokens a sus propietarios y se eliminan los tokens asociados
        _giveBackTokens(uid);
        //Se elimina la propuesta
        _proposals.deleteFromProposals(uid);
        
        if(_statusOpen){
            //Check if any proposal is Executable
            _checkExecutes();        
        }
        
    }

    
    // Realiza la compra de tokens a un participante.
    // Se requiere que el participante exista y que no se supere el maximo permitido de tokens establecido.
    function buyTokens() public payable VotingOpened ExistsParticipant{
        uint tokens = msg.value/_tokenValue;
        require(_tokens.totalSupply() + tokens <= _maxTokens,"No se pueden adquirir tantos tokens, sobrepasa los tokens permitidos");
        _participants[msg.sender] = SafeMath.add(_participants[msg.sender], msg.value);
        _tokens.mintImplement(msg.sender,tokens);
    }
    
    // Permite a un participante devolver los tokens no gastados en votaciones y recuperar el dinero invertido en ellos.
    // Se requiere que el participante exista y que tenga al menos 1 token.
    function sellTokens() payable public VotingOpened ExistsParticipant{
        uint tokens = _tokens.balanceOf(msg.sender);
        require(tokens > 0 , "No hay tokens para devolver.");
        uint amountToTransfer = SafeMath.mul(tokens , _tokenValue) ;
        //Se resta el saldo del participante, se destruyen los tokens y se transfiere los Wei al participante
        _participants[msg.sender] = SafeMath.sub(_participants[msg.sender], amountToTransfer);
        _tokens.burnImplement(msg.sender,tokens);
        payable(msg.sender).transfer(amountToTransfer);
    }
    
    // Devuelve el contrato ERC20.
    // Se requiere que el participante exista.
    function getERC20Voting() public view ExistsParticipant returns(address) {
        return address(_tokens);
    }
    
    // Devuelve un array con los identificadores de todas las propuestas pendientes de arpobar.
    function getPendingProposals() public view returns(bytes32[] memory){
        return _proposals.getPendingProposals();
    }
    
    // Devuelve un array con los identificadores de todas las propuestas ya aprobadas.
    function getApprovedProposals() public view returns(bytes32[] memory){
        return _proposals.getAcceptedProposals();
    }
    
    // Devuelve un array con los identificadores de todas las propuestas de tipo signaling.
    function getSinalingProposals() public view returns(bytes32[] memory){
        return _proposals.getSignalingProposals();
    }
    
    // Devuelve los datos asociados a una propuesta dado su identificador.
    // Se requiere que el identificador dado exista como propuesta.
    function getProposalInfo(bytes32 uid) public view returns(SharedStructs.ProposalStruct memory){
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uid);
        require( proposal.proposal != address(0x0),"Propuesta no existe");
        return proposal;
    }
    
    // Realiza el voto del participante que invoca esta función.
    // Se calcula los tokens necesarios para depositar los votos que se van a depositar,
    // Se comprueba que el participante posee los suficientes tokens para comprar los votos 
    // y que ha cedido (con approve) el uso de esos tokens a la cuenta del contrato de la votación.
    // Se transfiere la cantidad de tokens correspondiente desde la cuenta del participante a la cuenta de este contrato para poder operar con ellos.
    function stake(bytes32 uidProposal , uint nVotos) public ExistsParticipant VotingOpened PendingProposal(uidProposal) {
        // Se calcula los tokens necesarios para este numero de votos teniendo en cuenta
        // las posibles anteriores votaciones realizadas a la misma propuesta
        uint votosDone = _votos[msg.sender][uidProposal];
        uint nVotosNuevos = SafeMath.add(nVotos, votosDone);
        uint nTokensGastados = SafeMath.mul(votosDone,votosDone);
        uint nTokensNuevos = SafeMath.sub(SafeMath.mul(nVotosNuevos,nVotosNuevos), nTokensGastados);
        require(_tokens.allowance(msg.sender,address(this)) >= nTokensNuevos, "Numero de tokens insuficiente para realizar la votacion");
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uidProposal);
        _votos[msg.sender][uidProposal] = nVotosNuevos;
        _tokens.transferFromImplement(msg.sender, proposal.proposal, nTokensNuevos);
          proposal.totalVotos = SafeMath.add(proposal.totalVotos,nVotos);
        _proposals.setProposal(uidProposal,proposal);
        
         //Check if the proposal is Executable
        _executeProposal(uidProposal);            
        
    }
    
    // Emisor deposita la máxima cantidad de votos posible en la propuesta que se recibe como parámetro.
    // Se comprueba que ha cedido (con approve) el uso de esos tokens a la cuenta del contrato de la votación.
    function stakeAllToProposal(bytes32 uidProposal) public  ExistsParticipant VotingOpened PendingProposal(uidProposal) {
        // Se calcula los tokens posibles con los tokens propios actuales y teniendo en cuenta
        // las posibles anteriores votaciones realizadas a la misma propuesta
        uint votosDone = _votos[msg.sender][uidProposal];
        uint sumTokens = SafeMath.add(SafeMath.mul(votosDone,votosDone), _tokens.balanceOf(msg.sender));
        uint votosPosibles = _sqrt(sumTokens);
        uint tokensPosibles = (votosPosibles*votosPosibles)-(votosDone*votosDone);
        require(tokensPosibles > 0 , "No hay tokens suficientes para votar");
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uidProposal);
        _votos[msg.sender][uidProposal] = votosPosibles;
        _tokens.transferFromImplement(msg.sender, proposal.proposal, tokensPosibles);
        proposal.totalVotos = SafeMath.add(proposal.totalVotos ,SafeMath.sub(votosPosibles, votosDone));
        _proposals.setProposal(uidProposal,proposal);
        
          //Check if the proposal is Executable
        _executeProposal(uidProposal);      
    }
    
    // Elimina (si es posble)la cantidad indicada de votos depositados por el participante que invoca esta función
    // de la propuesta recibida y devolver los tokens utilizados.
    // El participante solo puede retirar de una propuesta votos que él haya depositado anteriormente.
    function withdrawFromProposal(bytes32 uidProposal , uint nVotos) public ExistsParticipant VotingOpened PendingProposal(uidProposal) {
        uint votosDone = _votos[msg.sender][uidProposal];
        require( votosDone > 0, "No hay votos que retirar de este participante en esta propuesta");
        uint actualVotos = votosDone - nVotos;
        require( actualVotos >= 0, "No se pueden retirar mas votos de los realizados");
        uint actualTokens = SafeMath.sub(SafeMath.mul(votosDone,votosDone) , (actualVotos*actualVotos));
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uidProposal);
        _votos[msg.sender][uidProposal] = actualVotos;
        _tokens.transferFromImplement( proposal.proposal, msg.sender, actualTokens);
        proposal.totalVotos = SafeMath.sub(proposal.totalVotos,nVotos);
        _proposals.setProposal(uidProposal,proposal);
        
         //Check if the proposal is Executable
        _executeProposal(uidProposal);    
    }
    
    // Elimina todos los votos depositados por el participante que invoca esta función de la propuesta indicada y devolver los tokens utilizados.
    // El participante solo puede retirar de una propuesta votos que él haya depositado anteriormente
    function withdrawAllFromProposal(bytes32 uidProposal) public ExistsParticipant VotingOpened PendingProposal(uidProposal) {
        uint votosDone = _votos[msg.sender][uidProposal];
        require( votosDone > 0, "No hay votos que retirar de este participante en esta propuesta");
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uidProposal);
         _votos[msg.sender][uidProposal] = 0;
        _tokens.transferFromImplement( proposal.proposal, msg.sender, SafeMath.mul(votosDone,votosDone) );
        proposal.totalVotos = SafeMath.sub(proposal.totalVotos,votosDone);
        _proposals.setProposal(uidProposal,proposal);
        
         //Check if the proposal is Executable
        _executeProposal(uidProposal);    
    }
    
    // Comprueba si se cumplen las condiciones para ejecutar la propuesta y la ejecuta
    // Se comprueba que el presupuesto del contrato sea > 0, el requerimiento (1)(el presupuesto del contrato de votación más el importe recaudado 
    // por los votos recibidos es suficiente para financiar la propuesta) y el requerimiento (2)(el número de votos recibidos supera el umbral definido)
    // Se transfiere al contrato el dinero presupuestado para su ejecucion y se actualiza el presupuesto disponible para otras propuestas.
    // Se eliminan/consumen los tokens asociados a los votos recibidos por la propuesta
    function _executeProposal(bytes32 uidProposal) internal {
        if(_isExecutable(uidProposal)){ //Se comprueban las condiciones para ejecutar la propuesta
            SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uidProposal);
            uint presupuestoObtenido = SafeMath.mul(proposal.totalVotos , _tokenValue);
            uint diferenciaPresupuestoObtenido = proposal.proposalInfo.budget - presupuestoObtenido;
            if(diferenciaPresupuestoObtenido > 0){ //Si el presupuesto obtenido no llega al presupuesto de la propuesta se resta lo que falta al presupuesto total
                _totalBudget =  SafeMath.sub(_totalBudget, diferenciaPresupuestoObtenido);
            }
            //Se eliminan todos los tokens obtenidos de la propuesta y se actualiza el estado de la propuesta
            _tokens.burnImplement(proposal.proposal, _tokens.balanceOf(proposal.proposal));
            proposal.accepted = true;
            _proposals.setProposal(uidProposal,proposal);
            _proposals.addAcceptedProposal(uidProposal);
            //Se transfiere el saldo presupuestado a la propuesta
            payable(proposal.proposal).transfer(proposal.proposalInfo.budget);
            //Se ejecuta la propuesta
            _proposals.executeProposal(uidProposal);            
        }
    }
    
    // Cierre del periodo de votación
    // Se requiere que sea el usuario creador de este contrato quien ejecute esta funcion
    // - Las propuestas no aprobadas son descartadas y el saldo de tokens en Wei recibidos por esas propuestas son devueltos a sus usuarios
    // - Las propuestas signaling son ejecutadas y el saldo de tokens en Wei recibidos por esas propuestas son devueltos a sus usuarios
    // - El presupuesto de la votacion no gastado es devuelto al usuario creador del contrato
    // - Los tokens no utilizados para votar son eliminados y el saldo en Wei es devuelto a sus propietarios
    function closeVoting() public payable OwnerContract {
        //Se ejecutan propuestas signaling y se devuelven el saldo a participantes
        bytes32[] memory proposals = _proposals.getSignalingProposals();// !!!!!!
        uint lengthArray = proposals.length;
         for(uint i = 0; i < lengthArray; i++){
            _proposals.executeProposal(proposals[i]);
            _giveBackMoney(proposals[i]); 
        }
        
        //Se iteran las propuestas aun pendientes y se cancelan devolvieno el saldo a los participantes
        proposals = _proposals.getPendingProposals();// !!!!!!
        lengthArray = proposals.length;
        for(uint i = 0; i < lengthArray; i++){
            _cancelProposalClose(proposals[i]);
        }
        
        //Se eliminan los tokens pendientes de los usuarios y se les devuelve sus respectivos saldos
        _cleanAllTokensParticipants();
        //Se devuelve el presupuesto restante del contrato al owner
        if(_totalBudget > 0)
            payable(_owner).transfer(_totalBudget);
        //Se cierra la votacion
        _statusOpen = false;
    }
    
    
    /** FUNCIONES INTERNAS **/
    
    //Funcion interna que calcula la raiz cuadrada 
    function _sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    //Funcion interna que calcula el umbral con fixedpoints(no funcionan y por eso lo he hecho con desplazamiento de 18, el numero 52429 se corresponde con el 0.2 constante)
    function _getUmbral(bytes32 uidProposal) internal view returns(uint256){
        //ufixed256x18 totalBudget = ufixed256x18(_totalBudget);
        //ufixed256x18 proposalBudget = ufixed256x18(_proposals.getProposal(uidProposal).proposalInfo.budget);
        //ufixed256x18 k = 0.2;
        //ufixed256x18 umbral = ( k + (proposalBudget/totalBudget)* ufixed256x18(_arrayParticipants.length) + ufixed256x18(_proposals.getArrayProposals().length));
        //uint256 ret = uint256(umbral>>18);
        uint256 proposalBudget = _proposals.getProposal(uidProposal).proposalInfo.budget;
        uint256 totalBudget = _totalBudget;
        uint256 division = (proposalBudget /totalBudget);
        unchecked {
            uint256 parteUmbral = (52429  + (division << 18) ); //0.2 + division
            uint256 ret = (parteUmbral >> 18);
            uint256 umbral = (ret *_arrayParticipants.length) + _proposals.getArrayProposals().length;
        return umbral;
        }
    }
    


    //Funcion interna que calcula si la propuesta se puede ejecutar/aceptar
    function _isExecutable(bytes32 uidProposal) internal view returns(bool){
        if(_totalBudget > 0 ){ // Comprueba si queda presupuesto del contrato para financiar propuestas
            SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uidProposal);
            if(SafeMath.add(_totalBudget , SafeMath.mul(proposal.totalVotos , _tokenValue)) > proposal.proposalInfo.budget){ // Se comprueba el requerimiento (1) Se ssupera el presupuesto de la propuesta
                uint umbral = _getUmbral(uidProposal);
                if(proposal.totalVotos > umbral) // Se comprueba si se supera el requerimiento(2), el umbral de votos de la propuesta
                    return true;
            }
        }
        return false;
    }
    
    //Funcion interna que se encarga de cancelar una propuesta existente no aprobada y devolver los tokens a sus propietarios
    function _cancelProposalClose(bytes32 uid) internal {
        SharedStructs.ProposalStruct memory proposal = _proposals.getProposal(uid);
        // Exista la propuesta
        require(proposal.proposal != address(0x0),"La propuesta no existe");
        // No este aprobada
        require(proposal.accepted == false, "La propesta fue ya aprobada");
        
        //Se devuelven los tokens a sus propietarios y se eliminan los tokens asociados
        _tokens.burnImplement(proposal.proposal, _tokens.balanceOf(proposal.proposal));
        _giveBackMoney(uid);
        
        //Se elimina la propuesta
        _proposals.deleteFromProposals(uid);
    }
    
    function _giveBackMoney(bytes32 uidProposal) internal {
        address[] memory participants = _arrayParticipants;
        uint length = participants.length;
        for(uint i = 0; i < length; i++){
            address participante = participants[i];
            uint nVotos = _votos[participante][uidProposal];
            if(nVotos > 0){
                 _votos[participante][uidProposal] = 0;
                 uint tokens = SafeMath.mul(nVotos,nVotos);
                 payable(participante).transfer(SafeMath.mul(tokens, _tokenValue));
            }
        }
    }
           
    function _giveBackTokens(bytes32 uidProposal) internal {
        address[] memory participants = _arrayParticipants;
        uint length = participants.length;
        for(uint i = 0; i < length; i++){
            address participante = participants[i];
            uint nVotos = _votos[participante][uidProposal];
            if(nVotos > 0){
                 _votos[participante][uidProposal] = 0;
                 _tokens.transferFromImplement(_proposals.getProposal(uidProposal).proposal, participante, SafeMath.mul(nVotos,nVotos) );
            }
        }
    }
    
    function _cleanAllTokensParticipants() internal{
        address[] memory participants = _arrayParticipants;
        uint length = participants.length;
        for(uint i = 0; i < length; i++){
             address participante = participants[i];
             uint tokens = _tokens.balanceOf(participante);
             _tokens.burnImplement(participante,tokens);
             payable(participante).transfer(SafeMath.mul(tokens , _tokenValue));
        }
    }
    
    function _checkExecutes() internal {
        bytes32[] memory array = getPendingProposals();
        uint length = array.length;
        for(uint i = 0; i < length; i++)
            _executeProposal(array[i]);
    }
    
}






