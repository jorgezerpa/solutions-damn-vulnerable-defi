## setup
1. Launch factories -> Safe Singlenton Factory and CreateX Factory 
2. Use CreateX factory, to deploy an `AuthorizerFactory`
3. Create an `AuthorizerUpgradeable` with `authorizerFactory.deployWithProxy(wards, aims, upgrader)` 
    - Creates a `TransparentProxy` with `AuthorizerUpgradeable` as implementation
    - Inits the contract -> SETS WARDS AND AIMS 
    - Set the upgrader address
4. 



INVARIANTS:
- For `AuthorizerUpgradeable` the only way to modify the wards map is by upgrading it and add a function that modifies such state. AKA after initiation this contract is "readOnly".

