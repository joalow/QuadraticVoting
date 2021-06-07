// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./ERC20/contracts/ERC20.sol";

contract TokenManager is ERC20{
    
    address _owner;
    
    constructor (string memory name, string memory symbol) ERC20(name,symbol){_owner = msg.sender;}
    
    
    // Llama a la funcion _mint del contrato ERC20,
    // Crea/Suma la cantidad de tokens amount a la cuenta account
    // Se requiere permisos para el msg.sender 
    function mintImplement(address account, uint256 amount) external {
        //Controlar quien lo ejecuta
        require(msg.sender == _owner,"ERC20: solo el propietario del contrato puede acceder.");
        //Controlar amount sea > 0
        require(amount > uint256(0),"ERROR: cantidad no valida");
        //Controlar account existente ya se realiza en el contrato ERC20
        //Llamada funcion contrato ERC20
        _mint(account,amount);
        //Incrementar premisos msg.sender
        _approve(account, _msgSender(), allowance(account, _msgSender()) + amount);
    }
    
    // Llama a la funcion _burn del contrato ERC20,
    // Destruye/Resta la cantidad de tokens amount a la cuenta account
    // Se requiere que se tienen tokens necesarios y con permisos para el msg.sender
    function burnImplement(address account, uint256 amount) public virtual {
        //Controlar quien lo ejecuta
        require(msg.sender == _owner,"ERC20: solo el propietario del contrato puede acceder.");
        //Verificar que se tienen tokens necesarios
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: cantidad burn excedida de lo permitido");
        _burn(account, amount);
        //Decrementar la cantidad permitida
        _approve(account, _msgSender(), currentAllowance - amount);
    }

}

