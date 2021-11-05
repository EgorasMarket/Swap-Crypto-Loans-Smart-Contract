/* eslint-disable prefer-const */
/* global artifacts */

const EgorasDao = artifacts.require('EgorasDao')
const DiamondCutFacet = artifacts.require('DiamondCutFacet')
const DiamondLoupeFacet = artifacts.require('DiamondLoupeFacet')
const OwnershipFacet = artifacts.require('OwnershipFacet')
const EgorasPriceOracleFacet = artifacts.require('EgorasPriceOracleFacet')
const EgorasMultiAssetLoanFacet = artifacts.require('EgorasMultiAssetLoanFacet')

const FacetCutAction = {
  Add: 0,
  Replace: 1,
  Remove: 2
}

function getSelectors (contract) {
  const selectors = contract.abi.reduce((acc, val) => {
    if (val.type === 'function') {
      acc.push(val.signature)
      return acc
    } else {
      return acc
    }
  }, [])
  return selectors
}

module.exports = function (deployer, network, accounts) {
 deployer.deploy(EgorasPriceOracleFacet);
 deployer.deploy(EgorasMultiAssetLoanFacet);

  deployer.deploy(DiamondCutFacet)
  deployer.deploy(DiamondLoupeFacet)
  deployer.deploy(OwnershipFacet).then(() => {
    const diamondCut = [
      [DiamondCutFacet.address, FacetCutAction.Add, getSelectors(DiamondCutFacet)],
      [DiamondLoupeFacet.address, FacetCutAction.Add, getSelectors(DiamondLoupeFacet)],
      [EgorasPriceOracleFacet.address, FacetCutAction.Add, getSelectors(EgorasPriceOracleFacet)],
      [EgorasMultiAssetLoanFacet.address, FacetCutAction.Add, getSelectors(EgorasMultiAssetLoanFacet)],
      [OwnershipFacet.address, FacetCutAction.Add, getSelectors(OwnershipFacet)],
    ]
    return deployer.deploy(EgorasDao, diamondCut, [accounts[0]])
  })
}
 